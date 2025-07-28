# KRO (Kubernetes Resource Operator) Manifests

This directory contains KRO ResourceGraphDefinitions and instances for deploying the 2048 game with AWS resources managed through Kubernetes.

## 🤔 What is KRO?

**KRO (Kubernetes Resource Operator)** is a Kubernetes operator that enables you to create **custom APIs** for managing complex resource compositions. Think of it as a way to build your own Kubernetes resources that can create and manage multiple other resources as a single unit.

### **Key Concepts:**

**🎯 ResourceGraphDefinition (RGD):**

- A **template** that defines a new Kubernetes API
- Describes what resources should be created and how they relate to each other
- Acts as a **blueprint** for complex resource compositions

**📦 Resource Instances:**

- **Actual deployments** created from ResourceGraphDefinitions
- Contain the specific configuration values for your resources
- Can be customized per environment (dev, staging, prod)

**🔗 Resource Graphs:**

- KRO manages **relationships** between resources
- Handles **dependencies** and **ordering** automatically
- Provides **status tracking** across all managed resources

### **Why Use KRO?**

**🚀 Simplify Complex Deployments:**

- Deploy entire application stacks with a single YAML file
- Manage AWS resources alongside Kubernetes resources
- Handle complex resource dependencies automatically

**🎯 Create Reusable Abstractions:**

- Define once, deploy many times across environments
- Hide complexity behind simple, user-friendly APIs
- Enable self-service deployments for development teams

**📊 Better Operational Visibility:**

- Track status of entire resource compositions
- Get unified view of application and infrastructure health
- Simplify troubleshooting with clear resource relationships

### **KRO vs Other Tools:**

| Feature | KRO | Crossplane | Helm | Kustomize | Terraform |
|---------|-----|------------|------|-----------|-----------|
| **Maturity** | 🟡 Early stage | 🟢 Mature | 🟢 Very mature | 🟢 Mature | 🟢 Very mature |
| **Custom APIs** | ✅ Creates new K8s APIs | ✅ Composite Resources | ❌ Templates only | ❌ Overlays only | ❌ External tool |
| **Cloud Resources** | ✅ Via KRM (ACK, KCC, ASO) | ✅ Native providers | ❌ K8s only | ❌ K8s only | ✅ Native support |
| **Status Tracking** | ✅ Built-in | ✅ Resource status | ❌ Limited | ❌ None | ✅ State file |
| **GitOps Ready** | ✅ Native K8s | ✅ Native K8s | ✅ With ArgoCD | ✅ Native | ❌ Requires wrapper |
| **Resource Relationships** | ✅ Automatic | ✅ Composition functions | ❌ Manual | ❌ Manual | ✅ Dependency graph |
| **Learning Curve** | 🟡 Moderate | 🔴 Steep | 🟢 Easy | 🟢 Easy | 🟡 Moderate |
| **Resource Composition** | ✅ ResourceGraphs | ✅ Composite Resources | ❌ Chart dependencies | ❌ Base + overlays | ✅ Modules |
| **Multi-Cloud + KRM** | 🟡 Via multiple controllers (ACK/KCC/ASO) | ✅ Built-in providers | ❌ K8s only | ❌ K8s only | ✅ Multiple providers |
| **Kubernetes Native** | ✅ Fully native | ✅ Fully native | ✅ Native | ✅ Native | ❌ External |
| **K8s Resource Management** | ✅ Simple YAML templates | 🔴 Complex compositions | ✅ Simple templates | ✅ Simple overlays | ❌ External tool |
| **Provider Management** | ✅ KRM controllers handle it | 🔴 Manual provider lifecycle | ✅ No providers needed | ✅ No providers needed | ✅ Simple providers |
| **Debugging Complexity** | 🟡 Moderate | 🔴 Very complex | 🟢 Simple | 🟢 Simple | 🟡 Moderate |
| **Resource Drift** | ✅ K8s reconciliation | 🔴 Provider-dependent | ✅ K8s reconciliation | ✅ K8s reconciliation | 🟡 State-based |
| **Operational Overhead** | 🟢 Low | 🔴 High | 🟢 Low | 🟢 Low | 🟡 Moderate |

## 🎮 KRO in This Project

In our 2048 game project, KRO enables us to:

1. **🗄️ Manage AWS Resources** - Create DynamoDB tables and S3 buckets through Kubernetes
2. **🚀 Deploy Complete Stacks** - Single command deploys infrastructure + application
3. **🌍 Environment Management** - Same definitions, different configurations per environment
4. **🔧 Operational Simplicity** - Use `kubectl` to manage everything
5. **📈 Scale Complexity** - Handle complex resource relationships automatically

## 🏗️ Architecture

KRO enables **Kubernetes-native** management of AWS resources through ResourceGraphDefinitions (RGDs):

```text
┌─────────────────────────────────────┐
│        ResourceGraphDefinitions     │
├─────────────────────────────────────┤
│ • DynamoDB Table RGD                │
│ • S3 Backup Bucket RGD              │
│ • Game2048 Application RGD          │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│           Resource Instances        │
├─────────────────────────────────────┤
│ • DynamoDB leaderboard table        │
│ • S3 backup bucket                  │
│ • Complete 2048 application         │
└─────────────────────────────────────┘
```

## 📁 Directory Structure

```text
kubernetes/kro/
├── README.md                        # This file
├── deploy-kro.sh                   # Separate RGDs deployment script
├── deploy-stack.sh                 # Complete stack deployment script
├── dynamodb-rgd.yaml              # DynamoDB ResourceGraphDefinition
├── s3-rgd.yaml                     # S3 ResourceGraphDefinition
├── game2048-app-rgd.yaml          # Application ResourceGraphDefinition
├── game2048-stack-rgd.yaml        # Complete stack ResourceGraphDefinition
└── instances/
    ├── dynamodb-instance.yaml      # DynamoDB table instance
    ├── s3-instance.yaml            # S3 bucket instance
    ├── app-instance.yaml           # Application instance
    └── game2048-stack-instance.yaml # Complete stack instance
```

## 🚀 Prerequisites

Before deploying KRO resources, ensure you have:

1. **EKS Cluster** deployed with OpenTofu
2. **KRO installed** on the cluster
3. **ACK Controllers** for DynamoDB and S3
4. **NGINX Ingress Controller** installed

### Quick Setup

```bash
# 1. Deploy infrastructure
cd ../../opentofu
tofu apply

# 2. Configure kubectl
aws eks --region eu-west-1 update-kubeconfig --name game2048-dev-cluster

# 3. Install KRO
../../scripts/kro_install.sh

# 4. Install ACK controllers
../../scripts/ack_controller_install.sh dynamodb
../../scripts/ack_controller_install.sh s3
```

## 🎯 ResourceGraphDefinitions

### 1. DynamoDB Table RGD (`dynamodb-rgd.yaml`)

Creates a **DynamoDB table** with:

- **Primary key**: `id` (String)
- **Global Secondary Index**: `ScoreIndex` for leaderboard queries
- **Point-in-time recovery** enabled
- **Server-side encryption** enabled
- **Configurable billing mode** (PAY_PER_REQUEST or PROVISIONED)

**Generated Resources:**

- DynamoDB Table (via ACK)
- ConfigMap with table configuration
- Service Account with IAM role

### 2. S3 Backup Bucket RGD (`s3-rgd.yaml`)

Creates an **S3 bucket** with:

- **Versioning** enabled
- **Server-side encryption** (AES256 or KMS)
- **Lifecycle policies** for cost optimization
- **Public access blocked** for security
- **Bucket policy** for application access

**Generated Resources:**

- S3 Bucket (via ACK)
- Bucket Policy for access control
- ConfigMap with bucket configuration
- Service Account with IAM role

### 3. Game2048 Application RGD (`game2048-app-rgd.yaml`)

Creates the **complete application** with:

- **Backend and Frontend** deployments
- **Services** for internal communication
- **Ingress** for external access
- **HPA** for auto-scaling
- **ConfigMaps** for configuration

**Generated Resources:**

- Namespace
- Deployments (backend, frontend)
- Services (ClusterIP)
- Ingress (NGINX)
- HorizontalPodAutoscalers
- ConfigMaps

## 🚀 Deployment

### Quick Deploy

```bash
# Deploy everything with your AWS account ID
./deploy-kro.sh --aws-account-id 123456789012 --bucket-suffix mycompany

# Dry-run to preview changes
./deploy-kro.sh --aws-account-id 123456789012 --dry-run

# Deploy only ResourceGraphDefinitions
./deploy-kro.sh --aws-account-id 123456789012 --skip-instances
```

### Manual Deployment

1. **Deploy ResourceGraphDefinitions:**

   ```bash
   kubectl apply -f dynamodb-rgd.yaml
   kubectl apply -f s3-rgd.yaml
   kubectl apply -f game2048-app-rgd.yaml
   ```

2. **Wait for RGDs to be ready:**

   ```bash
   kubectl get resourcegraphdefinitions -n kro
   ```

3. **Update instance files** with your AWS account ID and bucket suffix

4. **Deploy instances:**

   ```bash
   kubectl apply -f instances/dynamodb-instance.yaml
   kubectl apply -f instances/s3-instance.yaml
   kubectl apply -f instances/app-instance.yaml
   ```

## 🔧 Configuration

### DynamoDB Instance Configuration

```yaml
spec:
  tableName: "game2048-leaderboard"
  region: "eu-west-1"
  billingMode: "PAY_PER_REQUEST"  # or "PROVISIONED"
  pointInTimeRecovery: true
  serverSideEncryption: true
```

### S3 Instance Configuration

```yaml
spec:
  bucketName: "game2048-backup-unique-suffix"
  region: "eu-west-1"
  versioning: true
  encryption:
    enabled: true
    algorithm: "AES256"  # or "aws:kms"
  lifecycle:
    enabled: true
    transitionToIA: 30
    transitionToGlacier: 90
    expiration: 365
```

### Application Instance Configuration

```yaml
spec:
  backend:
    image: "2048-backend:latest"
    replicas: 3
  frontend:
    image: "2048-frontend:latest"
    replicas: 3
  ingress:
    enabled: true
    hostname: "2048.local"
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPU: 70
```

## 🔍 Monitoring and Troubleshooting

### Check Resource Status

```bash
# ResourceGraphDefinitions
kubectl get resourcegraphdefinitions -n kro

# Application resources
kubectl get all -n game-2048

# AWS resources (via ACK)
kubectl get tables.dynamodb.services.k8s.aws -n game-2048
kubectl get buckets.s3.services.k8s.aws -n game-2048
```

### View Logs

```bash
# KRO controller logs
kubectl logs -n kro -l app.kubernetes.io/name=kro

# Application logs
kubectl logs -n game-2048 -l app.kubernetes.io/component=backend
kubectl logs -n game-2048 -l app.kubernetes.io/component=frontend

# ACK controller logs
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-dynamodb-controller
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-s3-controller
```

### Common Issues

1. **RGD not creating CRD:**
   - Check KRO controller logs
   - Verify RGD syntax with `kubectl describe resourcegraphdefinition`

2. **AWS resources not created:**
   - Ensure ACK controllers are installed and running
   - Check IAM permissions for service accounts
   - Verify AWS credentials and region

3. **Application pods not starting:**
   - Check image availability
   - Verify ConfigMap and Secret references
   - Check resource limits and node capacity

## 🧹 Cleanup

### Remove All Resources

```bash
# Remove instances
kubectl delete -f instances/

# Remove ResourceGraphDefinitions
kubectl delete -f dynamodb-rgd.yaml
kubectl delete -f s3-rgd.yaml
kubectl delete -f game2048-app-rgd.yaml

# Remove namespace
kubectl delete namespace game-2048
```

### Remove KRO

```bash
../../scripts/kro_uninstall.sh --remove-crds --force
```

## 🎯 Benefits of KRO Approach

**Kubernetes-Native:**

- ✅ **Declarative** - Define desired state in YAML
- ✅ **GitOps friendly** - Version control and CI/CD integration
- ✅ **kubectl compatible** - Use familiar Kubernetes tools

**Composable:**

- ✅ **Reusable RGDs** - Define once, use many times
- ✅ **Parameterized** - Customize instances for different environments
- ✅ **Modular** - Separate concerns (database, storage, application)

**Production Ready:**

- ✅ **Resource relationships** - Proper dependencies and ordering
- ✅ **Status tracking** - Monitor resource creation and health
- ✅ **Error handling** - Built-in validation and error reporting

This approach provides **Infrastructure as Code** for both Kubernetes and AWS resources, managed entirely through Kubernetes APIs! 🚀
