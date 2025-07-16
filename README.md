# 2048 Game

A modern, responsive 2048 game built with React frontend and Go backend, featuring smooth animations, dark/light themes, and a professional menu system.

## 🎮 Features

- **Smooth tile movements** with polished animations
- **Dark/Light theme** toggle
- **Touch/swipe support** for mobile devices
- **Menu system** with game options and instructions
- **Score tracking** with persistent best score
- **Responsive design** for all screen sizes

## 🏗️ Architecture

- **Frontend**: React + Vite + Tailwind CSS
- **Backend**: Go with RESTful API
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

The game will be available at `http://localhost:3000` with the backend API running on port 8000.

## ☸️ Kubernetes Deployment

### Prerequisites
- Kubernetes cluster
- kubectl configured
- NGINX Ingress Controller

### Deploy
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
kubectl delete namespace game-2048
```

## 🎯 Game Controls

- **Desktop**: Arrow keys to move tiles
- **Mobile**: Swipe to move tiles
- **Goal**: Reach the 2048 tile to win!

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