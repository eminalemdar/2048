# 2048 Game

A modern, responsive 2048 game built with React frontend and Go backend, featuring smooth animations, dark/light themes, leaderboard system, and persistent score storage.

## 🎮 Features

- **Smooth tile movements** with polished animations
- **Dark/Light theme** toggle
- **Touch/swipe support** for mobile devices
- **Menu system** with game options and instructions
- **Global leaderboard** with persistent score storage
- **Multiple storage backends** (DynamoDB, S3, JSON fallback)
- **Score tracking** with game statistics (moves, duration)
- **Responsive design** for all screen sizes

## 🏗️ Architecture

- **Frontend**: React + Vite + Tailwind CSS
- **Backend**: Go with RESTful API
- **Database**: AWS DynamoDB (with S3 backup support)
- **Containerized**: Docker & Docker Compose
- **Kubernetes ready**: Production manifests included
- **KRO support**: Kubernetes Resource Operator for simplified AWS resource management

## 🚀 Running Locally

### Local Prerequisites

- Docker and Docker Compose

### Quick Start

```bash
# Clone and run
docker-compose up --build

# Access the game
open http://localhost:3000
```

The game will be available at `http://localhost:3000` with:

- Backend API on port 8000
- DynamoDB Local on port 8001
- Persistent leaderboard storage

## 📋 Installation Guide

This guide provides step-by-step instructions for deploying the 2048 game application on AWS using modern Kubernetes tooling.

### Deployment Architecture

The application uses the following components:

- **EKS Cluster**: Managed Kubernetes cluster on AWS
- **KRO**: Kubernetes Resource Operator for resource composition
- **ACK Controllers**: AWS Controllers for Kubernetes (IAM, DynamoDB, S3)
- **ALB**: Application Load Balancer for ingress
- **DynamoDB**: NoSQL database for game sessions and leaderboard
- **IAM Roles**: Service Account (IRSA) for secure AWS access

### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- AWS CLI configured with appropriate credentials
- kubectl installed
- Docker installed (for building images)

### Step 1: Deploy AWS Infrastructure

Deploy the underlying AWS infrastructure (EKS cluster, VPC, IAM roles) using OpenTofu:

```bash
# Use the provided infrastructure deployment script
./scripts/deploy_infrastructure.sh
```

This script will:

- Initialize OpenTofu configuration
- Deploy EKS cluster with necessary networking
- Set up IAM roles and policies
- Configure kubectl context

### Step 2: Install ACK Controllers

Install AWS Controllers for Kubernetes (ACK) to manage AWS resources from Kubernetes:

```bash
# Install required ACK controllers
# Usage: ./scripts/ack_controller_install.sh <service> <cluster-name> <region>
./scripts/ack_controller_install.sh iam game2048-dev eu-west-1
./scripts/ack_controller_install.sh dynamodb game2048-dev eu-west-1
./scripts/ack_controller_install.sh s3 game2048-dev eu-west-1
```

**Note**: The cluster name and region should match what was deployed in Step 1. You can get the actual values:

```bash
# Get cluster name and region from OpenTofu output
cd opentofu
CLUSTER_NAME=$(tofu output -raw eks_cluster_id)
AWS_REGION=$(tofu output -raw aws_region)
echo "Cluster: $CLUSTER_NAME, Region: $AWS_REGION"

# Then use these values in the ACK installation
./scripts/ack_controller_install.sh iam $CLUSTER_NAME $AWS_REGION
```

These controllers enable Kubernetes to manage AWS resources like DynamoDB tables and IAM roles declaratively.

### Step 3: Install KRO

Install the Kubernetes Resource Operator for simplified resource management:

```bash
# Install KRO
./scripts/kro_install.sh
```

KRO provides a higher-level abstraction for managing complex Kubernetes resource compositions.

### Step 4: Deploy KRO Application

#### Option A: Automated Deployment (Recommended)

Use the automated deployment script that handles proper ordering and waits for resources:

```bash
# Deploy everything with proper dependency management
./scripts/deploy_kro_application.sh
```

This script will:

- Deploy all ResourceGraphDefinitions (IAM, DynamoDB, Game Sessions, S3, Application) and wait for them to be active
- Deploy application instances in the correct dependency order (S3 bucket → DynamoDB tables → IAM role → Application)
- Wait for each resource to be ready before proceeding
- Verify the deployment with comprehensive health checks (pod readiness, ALB health)
- Provide access information and monitoring commands

#### Option B: Manual Deployment

Deploy resources manually if you prefer step-by-step control:

```bash
# Step 4a: Deploy ResourceGraphDefinitions
kubectl apply -f kubernetes/kro/iam-rgd.yaml
kubectl apply -f kubernetes/kro/dynamodb-rgd.yaml
kubectl apply -f kubernetes/kro/game-sessions-rgd.yaml
kubectl apply -f kubernetes/kro/s3-rgd.yaml
kubectl apply -f kubernetes/kro/game2048-app-rgd.yaml

# Wait for RGDs to be active
kubectl get rgd -n kro
# All should show STATE: Active

# Step 4b: Deploy Application Instances
kubectl apply -f kubernetes/kro/instances/s3-instance.yaml
kubectl apply -f kubernetes/kro/instances/game2048-leaderboard-table.yaml
kubectl apply -f kubernetes/kro/instances/game2048-sessions-table.yaml
kubectl apply -f kubernetes/kro/instances/game2048-backend-iam-role.yaml
kubectl apply -f kubernetes/kro/instances/game2048-app-instance.yaml

# Check deployment status
kubectl get pods -n game-2048
kubectl get table -n kro
kubectl get bucket -n kro
kubectl get ingress -n game-2048
```

### Step 5: Access the Application

Once deployed, access the application via the ALB ingress:

```bash
# Get the ALB URL
kubectl get ingress game2048-ingress -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# The game will be available at: http://<ALB-URL>
```

### 🎉 Installation Complete

Your 2048 game application is now deployed with:

- ✅ **Scalable backend** (2 replicas with auto-scaling)
- ✅ **Responsive frontend** (2 replicas with load balancing)
- ✅ **Persistent leaderboard** (DynamoDB with automatic backups)
- ✅ **Backup storage** (S3 bucket for data archival)
- ✅ **Secure access** (IAM roles with least privilege)
- ✅ **High availability** (Multi-AZ deployment)

### Verification

Verify the deployment is working:

```bash
# Check all pods are running
kubectl get pods -n game-2048

# Check AWS resources
kubectl get table -n kro          # DynamoDB tables
kubectl get bucket -n kro         # S3 buckets
kubectl get role.iam.services.k8s.aws -A  # IAM roles

# Test the backend health endpoint
curl http://<ALB-URL>/health

# Test the leaderboard API
curl http://<ALB-URL>/leaderboard/top
```

## ☁️ AWS Infrastructure Deployment (Manual)

For manual infrastructure deployment without the script:

### Deploy Infrastructure

```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init
tofu plan
tofu apply
```

### Configure kubectl

```bash
# Use the output command from tofu apply
aws eks --region eu-west-1 update-kubeconfig --name game2048-dev-cluster
```

## ☸️ Kubernetes Application Deployment (Traditional)

For traditional Kubernetes deployment without KRO:

### Deploy Application

```bash
cd kubernetes
./deploy.sh
```

### Access

```bash
# Port forward
kubectl port-forward -n game-2048 svc/frontend-service 3000:80

# Or add to /etc/hosts and use ingress
echo "<INGRESS_IP> 2048.local" >> /etc/hosts
# Then visit http://2048.local
```

## 🎛️ KRO (Kubernetes Resource Operator) Deployment

For a more Kubernetes-native approach to managing AWS resources, you can use KRO instead of traditional Kubernetes manifests.

### What is KRO?

KRO enables you to create **custom Kubernetes APIs** for managing complex resource compositions, including AWS resources through ACK controllers. It provides:

- **Declarative resource management** - Define infrastructure as Kubernetes resources
- **Resource relationships** - Automatic dependency handling and ordering
- **Reusable abstractions** - Create templates for common deployment patterns
- **GitOps ready** - Version control and CI/CD integration

### KRO Prerequisites

```bash
# Install KRO
./scripts/kro_install.sh

# Install ACK controllers for AWS resources
./scripts/ack_controller_install.sh dynamodb
./scripts/ack_controller_install.sh s3
```

### Deploy with KRO

```bash
cd kubernetes/kro

# Deploy ResourceGraphDefinitions and instances
./deploy-kro.sh --aws-account-id YOUR_ACCOUNT_ID --bucket-suffix mycompany

# Check deployment status
kubectl get resourcegraphdefinitions -n kro
kubectl get all -n game-2048
```

### KRO Benefits

- **Simplified operations** - Single command deploys infrastructure + application
- **Environment consistency** - Same definitions, different configurations
- **Resource composition** - Manage related resources as a single unit
- **Status tracking** - Built-in monitoring of resource creation and health
- **Status tracking** - Built-in monitoring of resource creation and health

See [kubernetes/kro/README.md](kubernetes/kro/README.md) for detailed KRO documentation and comparison with other tools.

## 📜 Script Reference

The following scripts are available to automate deployment tasks:

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/deploy_infrastructure.sh` | Deploy AWS infrastructure with OpenTofu | `./scripts/deploy_infrastructure.sh` |
| `scripts/ack_controller_install.sh` | Install ACK controllers | `./scripts/ack_controller_install.sh <service> <cluster-name> <region>` |
| `scripts/kro_install.sh` | Install KRO | `./scripts/kro_install.sh` |
| `scripts/build_and_push.sh` | Build and push Docker images | `./scripts/build_and_push.sh <component> <tag>` |

### Script Examples

```bash
# Deploy infrastructure
./scripts/deploy_infrastructure.sh

# Install ACK controllers (all three required)
./scripts/ack_controller_install.sh iam game2048-dev eu-west-1
./scripts/ack_controller_install.sh dynamodb game2048-dev eu-west-1
./scripts/ack_controller_install.sh s3 game2048-dev eu-west-1

# Install KRO
./scripts/kro_install.sh

# Build and push images
./scripts/build_and_push.sh backend v1
./scripts/build_and_push.sh frontend v1
```

## 🧹 Cleanup

### Remove Application

#### Option A: Automated Cleanup (Recommended)

```bash
# Remove application with proper dependency management
./scripts/cleanup_kro_application.sh

# Force cleanup without confirmation
./scripts/cleanup_kro_application.sh --force
```

#### Option B: Manual Cleanup

```bash
# Delete application instances (in reverse order)
kubectl delete -f kubernetes/kro/instances/game2048-app-instance.yaml
kubectl delete -f kubernetes/kro/instances/game2048-backend-iam-role.yaml
kubectl delete -f kubernetes/kro/instances/game2048-sessions-table.yaml
kubectl delete -f kubernetes/kro/instances/game2048-leaderboard-table.yaml
kubectl delete -f kubernetes/kro/instances/s3-instance.yaml

# Delete RGDs
kubectl delete -f kubernetes/kro/game2048-app-rgd.yaml
kubectl delete -f kubernetes/kro/s3-rgd.yaml
kubectl delete -f kubernetes/kro/iam-rgd.yaml
kubectl delete -f kubernetes/kro/game-sessions-rgd.yaml
kubectl delete -f kubernetes/kro/dynamodb-rgd.yaml

# Remove namespace
kubectl delete namespace game-2048
```

### Remove Infrastructure

```bash
# Remove AWS infrastructure
cd opentofu
tofu destroy
```

### Uninstall Controllers (Optional)

```bash
# Remove ACK controllers
helm uninstall ack-iam-controller -n ack-system
helm uninstall ack-dynamodb-controller -n ack-system
helm uninstall ack-s3-controller -n ack-system

# Remove KRO
kubectl delete -f https://github.com/awslabs/kro/releases/latest/download/kro.yaml
```

## 🔧 Troubleshooting

### Common Issues

**Pods not starting:**

```bash
# Check pod status and logs
kubectl get pods -n game-2048
kubectl logs <pod-name> -n game-2048
```

**DynamoDB permission errors:**

```bash
# Verify IAM role is attached to service account
kubectl get serviceaccount game2048-backend -n game-2048 -o yaml
# Look for eks.amazonaws.com/role-arn annotation
```

**Ingress not accessible:**

```bash
# Check ALB controller is running
kubectl get pods -n kube-system | grep aws-load-balancer-controller

# Verify ingress status
kubectl describe ingress game2048-ingress -n game-2048
```

**RGD not active:**

```bash
# Check RGD status
kubectl get rgd -n kro
kubectl describe rgd <rgd-name> -n kro
```

### Useful Commands

```bash
# Check all resources
kubectl get all -n game-2048

# View application logs
kubectl logs -f -l app.kubernetes.io/name=game2048-backend -n game-2048

# Test backend API
kubectl port-forward svc/game2048-backend-service 8000:8000 -n game-2048
curl http://localhost:8000/health

# Check DynamoDB tables
kubectl get table -n kro
```

## 🎯 Game Features

### Controls

- **Desktop**: Arrow keys to move tiles
- **Mobile**: Swipe to move tiles
- **Goal**: Reach the 2048 tile to win!

### Leaderboard

- **Submit scores** after each game
- **Global rankings** with top 10 players
- **Game statistics** (moves, duration, score)
- **Persistent storage** across sessions

### Storage Options

- **DynamoDB**: Primary database for leaderboard (AWS managed NoSQL)
- **S3 Backup**: Optional cloud backup (configure AWS credentials)
- **JSON Fallback**: Local file storage if databases unavailable

## 🛠️ Development

### Backend (Go)

```bash
cd backend
go run .
```

### Frontend (React)

```bash
cd frontend
npm install
npm run dev
```

---

Enjoy the game! 🎮
