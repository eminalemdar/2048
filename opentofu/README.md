# 2048 Game Infrastructure with OpenTofu

This directory contains OpenTofu configuration to provision core AWS infrastructure for the 2048 game using **public modules** for best practices and maintainability.

## 🏗️ Infrastructure Components

### Core Infrastructure (OpenTofu)

- **VPC** with public/private subnets across 2 AZs (using `terraform-aws-modules/vpc/aws`)
- **EKS Cluster with Auto Mode** — AWS provisions and scales nodes, and manages
  cluster DNS, pod/service networking, block storage and load balancing as core
  components (using `terraform-aws-modules/eks/aws`)
- **EKS Capabilities** — ACK and kro, managed by AWS outside the cluster
- **IAM Roles & Policies** for secure access
- **Security Groups** and networking

### Application Resources (KRO)

- **DynamoDB Table** for leaderboard storage → Managed by [kro](https://kro.run)
- **S3 Bucket** for backup storage → Managed by [kro](https://kro.run)

## 🚀 Quick Start

### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- AWS CLI configured with appropriate credentials
- kubectl installed

### Deploy Infrastructure

#### Option 1: Automated Deployment (Recommended)

```bash
# Use the automated deployment script
../scripts/deploy_infrastructure.sh
```

This script will:

- Copy and customize terraform.tfvars
- Initialize OpenTofu
- Plan and apply the infrastructure
- Configure kubectl automatically

#### Option 2: Manual Deployment

1. **Copy and customize variables:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Initialize and deploy:**

   ```bash
   tofu init
   tofu plan
   tofu apply
   ```

3. **Configure kubectl:**

   ```bash
   # Use the output command from tofu apply
   CLUSTER_NAME=$(tofu output -raw eks_cluster_name)
   AWS_REGION=$(tofu output -raw aws_region)
   aws eks --region $AWS_REGION update-kubeconfig --name $CLUSTER_NAME
   ```

## 📋 Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `eu-west-1` |
| `project_name` | Project name | `game2048` |
| `environment` | Environment (dev/staging/prod) | `dev` |
| `vpc_cidr` | VPC CIDR block | `172.16.0.0/16` |
| `eks_cluster_version` | EKS Kubernetes version | `1.36` |
| `eks_auto_mode_node_pools` | Auto Mode node pools to enable | `["system", "general-purpose"]` |
| `ack_iam_role_policies` | Policies on the ACK capability role ⚠️ | `AdministratorAccess` |
| `kro_access_policy_arn` | Access policy for the kro capability ⚠️ | `AmazonEKSClusterAdminPolicy` |
| `eks_access_entries` | EKS access entries for cluster access | `{}` |
| `cluster_endpoint_public_access` | Expose the API server publicly | `true` |
| `cluster_endpoint_public_access_cidrs` | CIDRs allowed to reach the API server | `["0.0.0.0/0"]` |

## 🔧 Module Usage

### VPC Module

- **Source**: `terraform-aws-modules/vpc/aws`
- **Features**: Multi-AZ setup, NAT gateways, proper Kubernetes tags
- **Customization**: Modify `vpc.tf` for different subnet configurations

### EKS Module  

- **Source**: `terraform-aws-modules/eks/aws`
- **Features**: Auto Mode compute/networking/storage/load balancing, OIDC
  provider for IRSA, access entries, ACK and kro capabilities
- **Customization**: Modify `eks.tf`; add a custom NodePool if you need
  specific instance shapes

## 🔐 Security Features

- **Private subnets** for EKS Auto Mode nodes
- **IAM roles** with least privilege access
- **OIDC provider** for service account authentication
- **VPC security groups** for network isolation
- **Auto Mode nodes** on immutable Bottlerocket AMIs, replaced at most every
  21 days, with no SSH/SSM access

## 💰 Cost Optimization

- **EKS Auto Mode** right-sizes and consolidates nodes automatically, and
  scales to zero nodes when nothing is scheduled
- **One NAT gateway per AZ** — two in total. This is a deliberate cost *increase*
  for availability: a single shared gateway is cheaper but becomes a
  cross-AZ dependency. Set `single_nat_gateway = true` in `vpc.tf` to halve it.
- **Proper resource tagging** for cost allocation

> Auto Mode adds a management fee per vCPU-hour on top of EC2, and each EKS
> Capability bills hourly plus per managed resource. Worth knowing before
> leaving a demo cluster running.

## 🧹 Cleanup

To destroy all infrastructure:

```bash
tofu destroy
```

⚠️ **Warning**: This will permanently delete all resources and data!

## 📊 Outputs

After deployment, you'll get:

- **VPC details**: ID, CIDR, subnet IDs
- **EKS cluster**: Endpoint, ARN, OIDC provider
- **kubectl command**: Ready-to-use cluster configuration
- **KRO setup info**: Values needed for KRO resource creation

## 🔧 Advanced Usage

### Multi-Environment Setup

```bash
# Development
tofu apply -var-file="dev.tfvars"

# Production  
tofu apply -var-file="prod.tfvars"
```

### Adding Custom Users

Cluster access uses EKS **access entries**. The legacy `aws-auth` ConfigMap
approach was removed in EKS module v21.

```hcl
eks_access_entries = {
  developer = {
    principal_arn = "arn:aws:iam::123456789012:user/developer"
    policy_associations = {
      admin = {
        policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = { type = "cluster" }
      }
    }
  }
}
```

## 🧩 EKS Capabilities (ACK and kro)

ACK and kro are **EKS Capabilities**, not in-cluster installs. They are declared
in `eks.tf` as `module.ack` and `module.kro`, run on AWS-managed infrastructure
outside your cluster, and install their own CRDs. There is nothing to helm
install, scale or patch — and no controller pods consuming node capacity.

### Enable / disable

They are created and destroyed with the rest of the stack:

```bash
tofu apply     # enables the ACK and kro capabilities
tofu destroy   # removes them
```

To drop one, delete its module block (and, for kro, the
`aws_eks_access_policy_association.kro` resource) and re-apply.

### Check status

```bash
CLUSTER_NAME=$(tofu output -raw eks_cluster_name)
AWS_REGION=$(tofu output -raw aws_region)

aws eks list-capabilities --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
aws eks describe-capability --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --capability-name <name> --query 'capability.status'
```

### ⚠️ Permissions warning

The defaults in `variables.tf` are the AWS getting-started ones and are
deliberately broad:

| Variable | Default | What it grants |
|----------|---------|----------------|
| `ack_iam_role_policies` | `AdministratorAccess` | ACK can create/modify/delete **any AWS resource** in the account |
| `kro_access_policy_arn` | `AmazonEKSClusterAdminPolicy` | kro can create **any Kubernetes resource** in the cluster |

Together these mean **anyone who can create a Kubernetes resource in this
cluster can create arbitrary AWS resources**. That is acceptable for a demo and
nothing else. Before real use:

- scope `ack_iam_role_policies` to IAM, DynamoDB and S3 only — the services
  these RGDs actually touch — or adopt ACK **IAM Role Selectors** for
  per-namespace least privilege
- replace `kro_access_policy_arn` with custom RBAC covering only the kinds your
  ResourceGraphDefinitions emit

### Deletion behaviour

Capabilities are created with `delete_propagation_policy = RETAIN`, so AWS
resources ACK created (DynamoDB tables, S3 buckets, IAM roles) **survive**
removal of the capability. Clean them up separately.

### KRO Features

- **ResourceGraphDefinitions** - Define complex AWS resource relationships
- **Kubernetes-native** - Manage AWS resources using kubectl
- **Declarative** - GitOps-friendly resource management
- **Composition** - Build higher-level abstractions
- **Alpha stage** - APIs may change, use with caution

## 🎯 Next Steps

`tofu apply` here also enables the ACK and kro capabilities — there is **nothing
to install into the cluster** (see [EKS Capabilities](#-eks-capabilities-ack-and-kro)
above). What remains is the application:

1. **✅ Deploy core infrastructure** with OpenTofu (this directory)
2. **Deploy the ResourceGraphDefinitions and application instances**:

   ```bash
   ../scripts/deploy_kro_application.sh game2048-dev eu-west-1
   ```

See the main [README.md](../README.md#-installation-guide) for the complete
step-by-step process, and [kubernetes/kro/README.md](../kubernetes/kro/README.md)
for what each RGD creates.

## 🎮 What This Supports

This infrastructure is the foundation for the 2048 game: an EKS Auto Mode
cluster, DynamoDB for the leaderboard and game sessions, an S3 backup bucket,
IRSA for the backend's AWS access, and an ALB for external traffic.

> **Not** included: horizontal pod autoscaling. The kro `Game2048Application`
> does not create an HPA, and EKS Auto Mode ships no metrics API, so nothing
> scales on load. See [kubernetes/README.md](../kubernetes/README.md) for the
> HPA that exists on the plain-manifest path and what it needs to work.
