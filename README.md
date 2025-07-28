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

## 🚀 Running Locally

### Prerequisites
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

**Enjoy the game! 🎮**