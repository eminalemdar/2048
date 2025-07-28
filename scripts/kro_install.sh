#!/bin/bash

# KRO (Kubernetes Resource Operator) Installation Script
# Usage: ./kro_install.sh [cluster-name] [region]

set -euo pipefail  # Exit on error, undefined vars, pipe failures

declare EKS_CLUSTER_NAME="${1:-game2048-dev-cluster}"
declare AWS_REGION="${2:-eu-west-1}"
declare KRO_NAMESPACE="kro"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v curl >/dev/null 2>&1 || missing_tools+=("curl")
    command -v jq >/dev/null 2>&1 || missing_tools+=("jq")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Please ensure kubectl is configured correctly"
        log_info "Run: aws eks --region ${AWS_REGION} update-kubeconfig --name ${EKS_CLUSTER_NAME}"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Get latest KRO version
get_kro_version() {
    log_info "Fetching latest KRO version from GitHub..."
    
    local KRO_VERSION
    KRO_VERSION=$(curl -sL https://api.github.com/repos/kro-run/kro/releases/latest | jq -r '.tag_name | ltrimstr("v")')
    
    if [ -z "$KRO_VERSION" ] || [ "$KRO_VERSION" = "null" ]; then
        log_error "Failed to fetch KRO version from GitHub"
        exit 1
    fi
    
    log_info "Latest KRO version: ${KRO_VERSION}"
    echo "$KRO_VERSION"
}

# Install KRO using Helm
install_kro() {
    log_info "======================================================"
    log_info "Installing KRO (Kubernetes Resource Operator)"
    log_info "======================================================"
    
    local KRO_VERSION
    KRO_VERSION=$(get_kro_version)
    
    log_info "Installing KRO version ${KRO_VERSION} using Helm..."
    
    # Clear any cached credentials that might cause issues
    helm registry logout ghcr.io >/dev/null 2>&1 || true
    
    # Install KRO using Helm
    if helm install kro "oci://ghcr.io/kro-run/kro/kro" \
        --namespace "${KRO_NAMESPACE}" \
        --create-namespace \
        --version="${KRO_VERSION}"; then
        log_info "KRO installation completed successfully"
    else
        log_error "Failed to install KRO"
        log_info "Troubleshooting tips:"
        log_info "1. Clear Helm credentials: helm registry logout ghcr.io"
        log_info "2. Check network connectivity to ghcr.io"
        log_info "3. Verify Helm version (3.x required)"
        exit 1
    fi
}

# Verify installation
verify_installation() {
    log_info "======================================================"
    log_info "Verifying KRO installation"
    log_info "======================================================"
    
    # Check Helm release
    log_info "Checking Helm release..."
    if helm list -n "${KRO_NAMESPACE}" | grep -q "kro"; then
        log_info "✅ Helm release found"
        helm list -n "${KRO_NAMESPACE}"
    else
        log_error "❌ Helm release not found"
        return 1
    fi
    
    echo ""
    
    # Wait for pods to be ready
    log_info "Waiting for KRO pods to be ready..."
    if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kro -n "${KRO_NAMESPACE}" --timeout=300s; then
        log_info "✅ KRO pods are ready"
    else
        log_warn "⚠️  Timeout waiting for pods to be ready"
    fi
    
    echo ""
    
    # Show pod status
    log_info "KRO pod status:"
    kubectl get pods -n "${KRO_NAMESPACE}"
    
    echo ""
    
    # Check CRDs
    log_info "Checking KRO Custom Resource Definitions..."
    local crd_count
    crd_count=$(kubectl get crd | grep -c "kro.run" || echo "0")
    if [ "$crd_count" -gt 0 ]; then
        log_info "✅ Found ${crd_count} KRO CRDs"
        kubectl get crd | grep "kro.run" || true
    else
        log_warn "⚠️  No KRO CRDs found"
    fi
}

# Show next steps
show_next_steps() {
    log_info "======================================================"
    log_info "KRO Installation Complete!"
    log_info "======================================================"
    
    echo ""
    log_info "Next steps:"
    echo "1. Create ResourceGraphDefinitions for your AWS resources"
    echo "2. Deploy DynamoDB and S3 resources using KRO"
    echo "3. Monitor resources: kubectl get pods -n ${KRO_NAMESPACE}"
    echo ""
    
    log_info "Useful commands:"
    echo "• Check KRO status: kubectl get pods -n ${KRO_NAMESPACE}"
    echo "• View KRO logs: kubectl logs -n ${KRO_NAMESPACE} -l app.kubernetes.io/name=kro"
    echo "• List KRO CRDs: kubectl get crd | grep kro.run"
    echo "• Uninstall KRO: ../scripts/kro_uninstall.sh"
    echo ""
    
    log_warn "Note: KRO is currently in alpha stage. APIs may change."
}

# Main execution
main() {
    log_info "Starting KRO installation"
    log_info "Cluster: ${EKS_CLUSTER_NAME}"
    log_info "Region: ${AWS_REGION}"
    log_info "Namespace: ${KRO_NAMESPACE}"
    
    check_prerequisites
    install_kro
    verify_installation
    show_next_steps
}

main "$@"