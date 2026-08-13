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

# The HPAs here target this path's deployment names (backend-deployment /
# frontend-deployment) and belong to the plain-manifest path only — the kro
# ResourceGraphDefinition deliberately does not manage an HPA.
#
# They read resource metrics from metrics.k8s.io, served by metrics-server. EKS
# Auto Mode does NOT provide it: it registers v1.metrics.eks.amazonaws.com,
# which backs the console's metrics view and does not satisfy an HPA. Apply them
# either way — they start working the moment metrics-server is installed — but
# say so plainly rather than leaving them stuck at <unknown>/70%.
print_status "Setting up auto-scaling..."
kubectl apply -f hpa.yaml

if ! kubectl get apiservices 2>/dev/null | grep -q "metrics.k8s.io"; then
    print_warning "No metrics.k8s.io API found — these HPAs will report <unknown> and never scale."
    print_warning "Install metrics-server to activate them:"
    print_warning "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
fi

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
# The Ingress carries no host rule: Auto Mode's ALB answers on its own generated
# DNS name, so there is nothing to add to /etc/hosts. The address can take a
# minute to appear while the load balancer provisions.
ALB_HOSTNAME=$(kubectl get ingress game-2048-ingress -n game-2048 \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$ALB_HOSTNAME" ]; then
    print_status "Access the game at: http://${ALB_HOSTNAME}"
else
    print_status "The ALB is still provisioning. Once it is ready, get the address with:"
    print_status "  kubectl get ingress game-2048-ingress -n game-2048"
fi
print_status "Or use port-forward: kubectl port-forward -n game-2048 svc/frontend-service 3000:80"

echo ""
print_status "Useful commands:"
echo "  View logs: kubectl logs -n game-2048 -l app=2048-backend"
echo "  Scale backend: kubectl scale -n game-2048 deployment/backend-deployment --replicas=3"
echo "  Delete deployment: kubectl delete namespace game-2048"