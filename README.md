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

## ☁️ AWS Infrastructure Deployment

### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- AWS CLI configured with appropriate credentials
- kubectl installed

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

## ☸️ Kubernetes Application Deployment

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

See [kubernetes/kro/README.md](kubernetes/kro/README.md) for detailed KRO documentation and comparison with other tools.

### Cleanup

```bash
# Remove Kubernetes resources
kubectl delete namespace game-2048

# Remove AWS infrastructure
cd opentofu
tofu destroy
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
