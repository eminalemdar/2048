#!/bin/bash

# Deploy 2048 Game Infrastructure
# This script ensures proper sequencing of OpenTofu deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENTOFU_DIR="$PROJECT_ROOT/opentofu"

echo "🚀 Starting infrastructure deployment..."

# Change to OpenTofu directory
cd "$OPENTOFU_DIR"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ terraform.tfvars not found. Please copy terraform.tfvars.example and configure it."
    exit 1
fi

# Initialize OpenTofu
echo "📦 Initializing OpenTofu..."
tofu init

# Plan the deployment
echo "📋 Planning deployment..."
tofu plan -out=tfplan

# Apply the deployment
echo "🔨 Applying deployment..."
tofu apply tfplan

# Update kubeconfig
echo "⚙️  Updating kubeconfig..."
CLUSTER_NAME=$(tofu output -raw eks_cluster_id)
AWS_REGION=$(tofu output -raw aws_region)

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "✅ Infrastructure deployment completed!"
echo "📝 Cluster name: $CLUSTER_NAME"
echo "🌍 Region: $AWS_REGION"
echo ""
echo "Next steps:"
echo "1. Verify cluster access: kubectl get nodes"
echo "2. Deploy your applications to the cluster"