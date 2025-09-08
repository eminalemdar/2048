# KRO (Kube Resource Orchestrator) Manifests

This directory contains KRO ResourceGraphDefinitions and instances for deploying the 2048 game with AWS resources managed through Kubernetes.

## 🤔 What is KRO?

**KRO (Kube Resource Orchestrator)** is a Kubernetes operator that enables you to create **custom APIs** for managing complex resource compositions. Think of it as a way to build your own Kubernetes resources that can create and manage multiple other resources as a single unit.

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
├── README.md                           # This file
├── dynamodb-rgd.yaml                  # DynamoDB ResourceGraphDefinition
├── game-sessions-rgd.yaml             # Game sessions table RGD
├── iam-rgd.yaml                       # IAM role for service accounts RGD
├── game2048-app-rgd.yaml             # Application ResourceGraphDefinition
├── s3-rgd.yaml                        # S3 ResourceGraphDefinition (optional)
└── instances/
    ├── game2048-leaderboard-table.yaml    # Leaderboard DynamoDB table
    ├── game2048-sessions-table.yaml       # Game sessions DynamoDB table
    ├── game2048-backend-iam-role.yaml     # IAM role for backend
    ├── game2048-app-instance.yaml         # Complete application
    └── s3-instance.yaml                   # S3 backup bucket (optional)
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
../../scripts/deploy_infrastructure.sh

# 2. Install KRO
../../scripts/kro_install.sh

# 3. Install ACK controllers
../../scripts/ack_controller_install.sh iam game2048-dev eu-west-1
../../scripts/ack_controller_install.sh dynamodb game2048-dev eu-west-1
../../scripts/ack_controller_install.sh s3 game2048-dev eu-west-1
```

## 🎯 ResourceGraphDefinitions

### 1. IAM Role RGD (`iam-rgd.yaml`)

Creates **IAM roles for service accounts** with:

- **IRSA trust policy** for EKS service accounts
- **DynamoDB permissions** for table access
- **Inline policies** for security
- **Proper resource ARNs** for least privilege

**Generated Resources:**

- IAM Role (via ACK IAM controller)
- Inline policies for DynamoDB access

### 2. DynamoDB Table RGD (`dynamodb-rgd.yaml`)

Creates **DynamoDB tables** with:

- **Primary key**: `id` (String)
- **Global Secondary Index**: `ScoreIndex` for leaderboard queries
- **Pay-per-request billing** for cost optimization
- **Proper tagging** for resource management

**Generated Resources:**

- DynamoDB Table (via ACK DynamoDB controller)

### 3. Game Sessions RGD (`game-sessions-rgd.yaml`)

Creates **game session storage** with:

- **Simple key schema** for session IDs
- **Pay-per-request billing**
- **Optimized for transient data**

**Generated Resources:**

- DynamoDB Table for game sessions

### 4. Game2048 Application RGD (`game2048-app-rgd.yaml`)

Creates the **complete application stack** with:

- **Backend and Frontend** deployments (2 replicas each)
- **Services** for internal communication
- **ALB Ingress** for external access
- **Service Account** with IAM role annotation
- **Health checks** and resource limits

**Generated Resources:**

- Namespace (`game-2048`)
- Backend Deployment + Service
- Frontend Deployment + Service  
- ALB Ingress with proper routing
- Service Account with IRSA annotation

### 5. S3 Backup RGD (`s3-rgd.yaml`) - Optional

Creates **S3 backup storage** with:

- **Versioning** enabled
- **Server-side encryption**
- **Lifecycle policies** for cost optimization
- **Public access blocked**

**Generated Resources:**

- S3 Bucket (via ACK S3 controller)

## 🚀 Deployment

### Quick Deploy (Recommended)

Follow the main installation guide in the root [README.md](../../README.md#-installation-guide) for the complete step-by-step process.

### Manual Deployment

1. **Deploy ResourceGraphDefinitions:**

   ```bash
   # Deploy all RGDs
   kubectl apply -f iam-rgd.yaml
   kubectl apply -f dynamodb-rgd.yaml
   kubectl apply -f game-sessions-rgd.yaml
   kubectl apply -f s3-rgd.yaml
   kubectl apply -f game2048-app-rgd.yaml
   ```

2. **Wait for RGDs to be ready:**

   ```bash
   kubectl get resourcegraphdefinitions -n kro
   # All should show STATE: Active
   ```

3. **Deploy instances:**

   ```bash
   # Deploy S3 bucket
   kubectl apply -f instances/s3-instance.yaml
   
   # Deploy DynamoDB tables
   kubectl apply -f instances/game2048-leaderboard-table.yaml
   kubectl apply -f instances/game2048-sessions-table.yaml
   
   # Deploy IAM role for backend
   kubectl apply -f instances/game2048-backend-iam-role.yaml
   
   # Deploy the application
   kubectl apply -f instances/game2048-app-instance.yaml
   ```

4. **Verify deployment:**

   ```bash
   # Check all resources
   kubectl get pods -n game-2048
   kubectl get ingress -n game-2048
   kubectl get table -n kro
   kubectl get bucket -n kro
   ```

## 🔧 Configuration

### IAM Role Instance Configuration

```yaml
apiVersion: kro.run/v1alpha1
kind: IAMRoleForServiceAccount
metadata:
  name: game2048-backend-iam-role
spec:
  roleName: "game2048-backend-role"
  serviceAccountName: "game2048-backend"
  serviceAccountNamespace: "game-2048"
  region: "eu-west-1"
```

### DynamoDB Instance Configuration

```yaml
apiVersion: kro.run/v1alpha1
kind: DynamoDBTable
metadata:
  name: game2048-leaderboard-dev
spec:
  tableName: "game2048-leaderboard-dev"
  region: "eu-west-1"
  billingMode: "PAY_PER_REQUEST"
```

### Application Instance Configuration

```yaml
apiVersion: kro.run/v1alpha1
kind: Game2048Application
metadata:
  name: game2048-dev
spec:
  name: "game2048"
  namespace: "game-2048"
  backendImage: "emnalmdr/2048-backend:latest"
  backendReplicas: 2
  frontendImage: "emnalmdr/2048-frontend:v5"
  frontendReplicas: 2
  tableName: "game2048-leaderboard-dev"
  region: "eu-west-1"
  ingressClass: "alb"
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
# Remove instances (in reverse order)
kubectl delete -f instances/game2048-app-instance.yaml
kubectl delete -f instances/game2048-backend-iam-role.yaml
kubectl delete -f instances/game2048-sessions-table.yaml
kubectl delete -f instances/game2048-leaderboard-table.yaml
kubectl delete -f instances/s3-instance.yaml

# Remove ResourceGraphDefinitions
kubectl delete -f game2048-app-rgd.yaml
kubectl delete -f s3-rgd.yaml
kubectl delete -f iam-rgd.yaml
kubectl delete -f game-sessions-rgd.yaml
kubectl delete -f dynamodb-rgd.yaml

# Remove namespace
kubectl delete namespace game-2048
```

### Remove KRO (Optional)

```bash
../../scripts/kro_uninstall.sh
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
