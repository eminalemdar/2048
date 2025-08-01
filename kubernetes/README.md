# Kubernetes Deployment

This directory contains traditional Kubernetes manifests for deploying the 2048 game application.

> **⚠️ Note**: For production deployments, we recommend using the **KRO-based approach** in the `kro/` directory, which provides better resource management and AWS integration.

## 🏗️ Prerequisites

1. **EKS Cluster** deployed via OpenTofu (see `../opentofu/README.md`)
2. **kubectl configured** to connect to your cluster
3. **ACK Controllers** installed for AWS resource management
4. **DynamoDB tables** created (manually or via ACK/KRO)

## 🚀 Traditional Deployment

### Quick Deploy

```bash
# Deploy using traditional manifests
./deploy.sh
```

### Manual Deployment

```bash
# Create namespace
kubectl apply -f namespace.yaml

# Deploy application components
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml

# Configure networking
kubectl apply -f ingress.yaml

# Optional: Enable auto-scaling
kubectl apply -f hpa.yaml
```

## 📁 Manifest Files

| File | Purpose |
|------|---------|
| `namespace.yaml` | Creates `game-2048` namespace |
| `backend-deployment.yaml` | Go backend deployment (2 replicas) |
| `backend-service.yaml` | Backend service (ClusterIP) |
| `frontend-deployment.yaml` | React frontend deployment (2 replicas) |
| `frontend-service.yaml` | Frontend service (ClusterIP) |
| `ingress.yaml` | ALB ingress for external access |
| `hpa.yaml` | Horizontal Pod Autoscaler |
| `configmap.yaml` | Application configuration |

## 🗄️ Database Requirements

The application requires DynamoDB tables for:

- **Leaderboard**: `game2048-leaderboard-dev`
- **Game Sessions**: `game2048-sessions-dev`

### Create Tables Manually

```bash
# Leaderboard table
aws dynamodb create-table \
  --table-name game2048-leaderboard-dev \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=score,AttributeType=N \
    AttributeName=timestamp,AttributeType=S \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --global-secondary-indexes \
    IndexName=ScoreIndex,KeySchema=[{AttributeName=score,KeyType=HASH},{AttributeName=timestamp,KeyType=RANGE}],Projection={ProjectionType=ALL} \
  --billing-mode PAY_PER_REQUEST

# Game sessions table
aws dynamodb create-table \
  --table-name game2048-sessions-dev \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

## 🔐 IAM Requirements

The backend pods need IAM permissions for DynamoDB access. Create an IAM role with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/game2048-leaderboard-dev",
        "arn:aws:dynamodb:*:*:table/game2048-sessions-dev",
        "arn:aws:dynamodb:*:*:table/game2048-leaderboard-dev/index/*",
        "arn:aws:dynamodb:*:*:table/game2048-sessions-dev/index/*"
      ]
    }
  ]
}
```

## 🌐 Access the Application

### Via ALB Ingress

```bash
# Get ALB URL
kubectl get ingress game2048-ingress -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access at: http://<ALB-URL>
```

### Via Port Forward

```bash
# Frontend
kubectl port-forward -n game-2048 svc/frontend-service 3000:80

# Backend API
kubectl port-forward -n game-2048 svc/backend-service 8000:8000
```

## 🔍 Monitoring

```bash
# Check pod status
kubectl get pods -n game-2048

# View logs
kubectl logs -f deployment/backend-deployment -n game-2048
kubectl logs -f deployment/frontend-deployment -n game-2048

# Check ingress
kubectl describe ingress game2048-ingress -n game-2048
```

## 🧹 Cleanup

```bash
# Delete all resources
kubectl delete namespace game-2048

# Or delete individual components
kubectl delete -f .
```

## 🎯 Recommended Approach

For production deployments, consider using:

1. **KRO-based deployment** (`../kro/README.md`) - Provides better AWS resource management
2. **Helm charts** - For templating and configuration management
3. **GitOps** - For automated deployments and configuration drift detection

See the main [README.md](../README.md) for the complete installation guide using modern tooling.
