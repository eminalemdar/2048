# Kubernetes Deployment

Kubernetes manifests for deploying the 2048 game to an EKS cluster with DynamoDB backend.

## 🏗️ Prerequisites

Before deploying the application, ensure you have:

1. **EKS Cluster** deployed via OpenTofu:

   ```bash
   cd ../opentofu
   tofu apply
   ```

2. **kubectl configured**:

   ```bash
   aws eks --region eu-west-1 update-kubeconfig --name game2048-dev-cluster
   ```

3. **AWS resources** created via KRO or ACK controllers

## 🚀 Quick Deploy

```bash
./deploy.sh
```

## 📁 Files

- `namespace.yaml` - Creates game-2048 namespace
- `*-deployment.yaml` - Application deployments
- `*-service.yaml` - Kubernetes services
- `ingress.yaml` - External access configuration
- `hpa.yaml` - Auto-scaling configuration
- `configmap.yaml` - Application configuration

## 🗄️ Database Setup Options

This deployment uses **AWS DynamoDB** as the primary database. Choose one of these approaches:

### Option 1: ACK Controllers (Recommended)

```bash
# Install DynamoDB controller
../scripts/ack_controller_install.sh dynamodb

# Install S3 controller for backups
../scripts/ack_controller_install.sh s3
```

### Option 2: KRO (Kubernetes Resource Operator)

```bash
# Install KRO using our script (recommended)
../scripts/kro_install.sh

# Deploy DynamoDB and S3 resources using KRO manifests
# (KRO manifests to be created separately)
```

### Option 3: Manual AWS CLI

```bash
# Create DynamoDB table manually
aws dynamodb create-table \
  --table-name game2048-leaderboard \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=score,AttributeType=N \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --global-secondary-indexes \
    IndexName=ScoreIndex,KeySchema=[{AttributeName=score,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
```

## 🌐 Access

### Port Forward

```bash
kubectl port-forward -n game-2048 svc/frontend-service 3000:80
```

### Ingress

Add to `/etc/hosts`:

```text
<INGRESS_IP> 2048.local
```

Visit: <http://2048.local>

## 🧹 Cleanup

```bash
kubectl delete namespace game-2048
```
