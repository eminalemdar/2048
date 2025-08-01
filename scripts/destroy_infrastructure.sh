#!/bin/bash

# Destroy 2048 Game Infrastructure
# This script safely destroys the OpenTofu-managed infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OPENTOFU_DIR="$PROJECT_ROOT/opentofu"

echo "🗑️  Starting infrastructure destruction..."

# Change to OpenTofu directory
cd "$OPENTOFU_DIR"

# Get cluster info before destruction
CLUSTER_NAME=$(tofu output -raw cluster_name 2>/dev/null || echo "unknown")
AWS_REGION=$(tofu output -raw region 2>/dev/null || echo "unknown")

echo "📋 Planning destruction..."
tofu plan -destroy -out=destroy-plan

echo "⚠️  WARNING: This will destroy the following infrastructure:"
echo "   - EKS Cluster: $CLUSTER_NAME"
echo "   - VPC and networking components"
echo "   - All associated AWS resources"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [ "$confirm" = "yes" ]; then
    echo "🔨 Destroying infrastructure..."
    tofu apply destroy-plan
    
    # Clean up kubeconfig entry
    if [ "$CLUSTER_NAME" != "unknown" ] && [ "$AWS_REGION" != "unknown" ]; then
        echo "🧹 Cleaning up kubeconfig..."
        kubectl config delete-context "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$CLUSTER_NAME" 2>/dev/null || true
        kubectl config delete-cluster "arn:aws:eks:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):cluster/$CLUSTER_NAME" 2>/dev/null || true
    fi
    
    echo "✅ Infrastructure destruction completed!"
else
    echo "❌ Destruction cancelled."
    rm -f destroy-plan
fi