# 2048 Game Infrastructure with OpenTofu

This directory contains OpenTofu configuration to provision core AWS infrastructure for the 2048 game using **public modules** for best practices and maintainability.

## 🏗️ Infrastructure Components

### Core Infrastructure (OpenTofu)

- **VPC** with public/private subnets across 2 AZs (using `terraform-aws-modules/vpc/aws`)
- **EKS Cluster** with managed node groups (using `terraform-aws-modules/eks/aws`)
- **IAM Roles & Policies** for secure access
- **Security Groups** and networking

### Application Resources (KRO)

- **DynamoDB Table** for leaderboard storage → Managed by [KRO](https://kro.dev)
- **S3 Bucket** for backup storage → Managed by [KRO](https://kro.dev)

## 🚀 Quick Start

### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- AWS CLI configured with appropriate credentials
- kubectl installed

### Deploy Infrastructure

1. **Copy and customize variables:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Initialize OpenTofu:**

   ```bash
   tofu init
   ```

3. **Plan the deployment:**

   ```bash
   tofu plan
   ```

4. **Apply the infrastructure:**

   ```bash
   tofu apply
   ```

5. **Configure kubectl:**

   ```bash
   # Use the output command from tofu apply
   aws eks --region eu-west-1 update-kubeconfig --name game2048-dev-cluster
   ```

6. **Install ACK Controllers (Optional):**

   ```bash
   # Install DynamoDB controller
   ../scripts/ack_controller_install.sh dynamodb
   
   # Install S3 controller
   ../scripts/ack_controller_install.sh s3
   ```

7. **Install KRO for application resources:**

   ```bash
   # Install KRO using our script (recommended)
   ../scripts/kro_install.sh
   
   # Deploy DynamoDB and S3 resources using KRO
   # (KRO manifests will be created separately)
   ```

## 📋 Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `eu-west-1` |
| `project_name` | Project name | `game2048` |
| `environment` | Environment (dev/staging/prod) | `dev` |
| `vpc_cidr` | VPC CIDR block | `172.16.0.0/16` |
| `eks_cluster_version` | EKS Kubernetes version | `1.28` |
| `eks_node_instance_types` | EC2 instance types for nodes | `["m5.xlarge"]` |
| `eks_auth_users` | Additional IAM users for cluster access | `[]` |

## 🔧 Module Usage

### VPC Module

- **Source**: `terraform-aws-modules/vpc/aws`
- **Features**: Multi-AZ setup, NAT gateways, proper Kubernetes tags
- **Customization**: Modify `vpc.tf` for different subnet configurations

### EKS Module  

- **Source**: `terraform-aws-modules/eks/aws`
- **Features**: Managed node groups, OIDC provider, aws-auth configmap
- **Customization**: Modify `eks.tf` for different node configurations

## 🔐 Security Features

- **Private subnets** for EKS worker nodes
- **IAM roles** with least privilege access
- **OIDC provider** for service account authentication
- **VPC security groups** for network isolation
- **Managed node groups** with automatic updates

## 💰 Cost Optimization

- **Managed EKS** with optimized instance types
- **Single NAT gateway per AZ** for high availability
- **On-demand instances** with auto-scaling
- **Proper resource tagging** for cost allocation

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

```hcl
eks_auth_users = [
  {
    userarn  = "arn:aws:iam::123456789012:user/developer"
    username = "developer"
    groups   = ["system:masters"]
  }
]
```

## 🎮 ACK Controller Management

### Install ACK Controllers

```bash
# Install DynamoDB controller
../scripts/ack_controller_install.sh dynamodb

# Install S3 controller  
../scripts/ack_controller_install.sh s3

# Install with custom cluster/region
../scripts/ack_controller_install.sh rds my-cluster us-west-2
```

### Remove ACK Controllers

```bash
# Remove DynamoDB controller
../scripts/ack_controller_cleanup.sh dynamodb

# Dry-run mode (preview only)
../scripts/ack_controller_cleanup.sh s3 --dry-run

# Force mode (no confirmations)
../scripts/ack_controller_cleanup.sh rds --force
```

### Available ACK Services

- **dynamodb** - DynamoDB tables and indexes
- **s3** - S3 buckets and policies
- **rds** - RDS databases and clusters
- **ec2** - EC2 instances and security groups
- **iam** - IAM roles and policies
- **lambda** - Lambda functions
- **sqs** - SQS queues
- **sns** - SNS topics

## 🎯 KRO Management

### Install KRO

```bash
# Install KRO using Helm (recommended)
../scripts/kro_install.sh

# Install with custom cluster/region
../scripts/kro_install.sh my-cluster us-west-2
```

### Remove KRO

```bash
# Remove KRO (preserves CRDs and custom resources)
../scripts/kro_uninstall.sh

# Dry-run mode (preview only)
../scripts/kro_uninstall.sh --dry-run

# Force mode (no confirmations)
../scripts/kro_uninstall.sh --force

# Remove everything including CRDs (destructive!)
../scripts/kro_uninstall.sh --remove-crds --force
```

### KRO Features

- **ResourceGraphDefinitions** - Define complex AWS resource relationships
- **Kubernetes-native** - Manage AWS resources using kubectl
- **Declarative** - GitOps-friendly resource management
- **Composition** - Build higher-level abstractions
- **Alpha stage** - APIs may change, use with caution

## 🎯 Next Steps

1. **Deploy core infrastructure** with OpenTofu
2. **Install ACK controllers** for AWS resource management
3. **Install KRO** on your EKS cluster
4. **Create KRO manifests** for DynamoDB and S3
5. **Deploy your application** to the cluster

This approach provides:

- ✅ **Separation of concerns** (infrastructure vs application resources)
- ✅ **Best practices** using community modules
- ✅ **Kubernetes-native** resource management with KRO and ACK
- ✅ **Maintainable** and **scalable** architecture
