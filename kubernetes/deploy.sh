#!/bin/bash

# 2048 Game Kubernetes Deployment Script
set -e

echo "🎮 Deploying 2048 Game to Kubernetes..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to Kubernetes cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

print_status "Connected to Kubernetes cluster"

# NOTE: images are pulled from the registry, not built here. These manifests
# run on EKS, where a locally built `2048-backend:latest` tag cannot be pulled
# by the nodes. Use ../scripts/build_and_push.sh to publish a new tag and update
# the image references in the deployment manifests.

# Apply Kubernetes manifests
print_status "Creating namespace..."
kubectl apply -f namespace.yaml

# Auto Mode provides load balancing, but the IngressClass pointing at it has to
# exist before an Ingress referencing "alb" can be reconciled.
print_status "Applying Auto Mode IngressClass..."
kubectl apply -f auto-mode-ingressclass.yaml

print_status "Applying ConfigMap..."
kubectl apply -f configmap.yaml

print_status "Deploying backend..."
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml

print_status "Deploying frontend..."
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml

print_status "Setting up ingress..."
kubectl apply -f ingress.yaml

print_status "Setting up auto-scaling..."
kubectl apply -f hpa.yaml

# Wait for deployments to be ready
print_status "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/backend-deployment -n game-2048
kubectl wait --for=condition=available --timeout=300s deployment/frontend-deployment -n game-2048

print_success "All deployments are ready!"

# Display status
echo ""
print_status "Deployment Status:"
kubectl get pods -n game-2048
echo ""
kubectl get services -n game-2048
echo ""
kubectl get ingress -n game-2048

echo ""
print_success "🎉 2048 Game deployed successfully!"
print_status "Access the game at: http://2048.local (add to /etc/hosts if needed)"
print_status "Or use port-forward: kubectl port-forward -n game-2048 svc/frontend-service 3000:80"

echo ""
print_status "Useful commands:"
echo "  View logs: kubectl logs -n game-2048 -l app=2048-backend"
echo "  Scale backend: kubectl scale -n game-2048 deployment/backend-deployment --replicas=3"
echo "  Delete deployment: kubectl delete namespace game-2048"