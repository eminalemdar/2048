#!/bin/bash

# KRO (Kubernetes Resource Operator) Uninstallation Script
# Usage: ./kro_uninstall.sh [options]

set -euo pipefail  # Exit on error, undefined vars, pipe failures

declare KRO_NAMESPACE="kro"

# Parse options
DRY_RUN=false
FORCE=false
REMOVE_CRDS=false

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

log_dry_run() {
    echo -e "${BLUE}[DRY-RUN]${NC} Would execute: $1"
}

# Show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would be deleted without actually deleting"
    echo "  --force         Skip confirmation prompts"
    echo "  --remove-crds   Also remove KRO Custom Resource Definitions"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive uninstall"
    echo "  $0 --dry-run          # Preview what will be deleted"
    echo "  $0 --force            # Uninstall without confirmation"
    echo "  $0 --remove-crds      # Also remove CRDs (destructive!)"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --remove-crds)
                REMOVE_CRDS=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        log_info "Please ensure kubectl is configured correctly"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Confirmation prompt
confirm_action() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo ""
    log_warn "This will remove the following KRO resources:"
    echo "  - Helm release: kro (in namespace ${KRO_NAMESPACE})"
    echo "  - KRO controller pods and services"
    echo "  - KRO namespace: ${KRO_NAMESPACE}"
    
    if [ "$REMOVE_CRDS" = true ]; then
        echo "  - KRO Custom Resource Definitions (CRDs)"
        echo "  - ALL ResourceGraphDefinitions and related resources"
        log_warn "⚠️  Removing CRDs will delete all KRO-managed resources!"
    else
        echo ""
        log_info "Note: CRDs and custom resources will be preserved"
        log_info "Use --remove-crds to also remove CRDs (destructive!)"
    fi
    
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in dry-run mode - no resources will be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

# Show current KRO resources
show_current_resources() {
    log_info "======================================================"
    log_info "Current KRO resources"
    log_info "======================================================"
    
    # Check Helm release
    log_info "Checking Helm release..."
    if helm list -n "${KRO_NAMESPACE}" 2>/dev/null | grep -q "kro"; then
        helm list -n "${KRO_NAMESPACE}"
    else
        log_warn "No KRO Helm release found"
    fi
    
    echo ""
    
    # Check pods
    log_info "Checking KRO pods..."
    if kubectl get pods -n "${KRO_NAMESPACE}" 2>/dev/null | grep -q "kro"; then
        kubectl get pods -n "${KRO_NAMESPACE}"
    else
        log_warn "No KRO pods found"
    fi
    
    echo ""
    
    # Check CRDs
    log_info "Checking KRO CRDs..."
    local crds
    crds=$(kubectl get crd 2>/dev/null | grep "kro.run" || echo "")
    if [ -n "$crds" ]; then
        echo "$crds"
    else
        log_warn "No KRO CRDs found"
    fi
    
    echo ""
    
    # Check custom resources
    log_info "Checking KRO custom resources..."
    local custom_resources=0
    kubectl api-resources --api-group="kro.run" 2>/dev/null | tail -n +2 | while read -r line; do
        if [ -n "$line" ]; then
            local resource_type
            resource_type=$(echo "$line" | awk '{print $1}')
            local count
            count=$(kubectl get "$resource_type" --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$count" -gt 0 ]; then
                log_warn "Found ${count} ${resource_type} resources"
                custom_resources=$((custom_resources + count))
            fi
        fi
    done || true
}

# Uninstall KRO Helm release
uninstall_helm_release() {
    log_info "======================================================"
    log_info "Removing KRO Helm release"
    log_info "======================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "helm uninstall kro -n ${KRO_NAMESPACE}"
        return 0
    fi
    
    # Check if release exists
    if helm list -n "${KRO_NAMESPACE}" 2>/dev/null | grep -q "kro"; then
        log_info "Uninstalling KRO Helm release..."
        if helm uninstall kro -n "${KRO_NAMESPACE}"; then
            log_info "✅ KRO Helm release removed successfully"
        else
            log_error "❌ Failed to remove KRO Helm release"
            return 1
        fi
    else
        log_warn "KRO Helm release not found"
    fi
    
    # Wait for pods to be terminated
    log_info "Waiting for KRO pods to be terminated..."
    kubectl wait --for=delete pods -l app.kubernetes.io/name=kro -n "${KRO_NAMESPACE}" --timeout=120s 2>/dev/null || log_warn "Timeout waiting for pods to terminate"
}

# Remove namespace
remove_namespace() {
    log_info "======================================================"
    log_info "Removing KRO namespace"
    log_info "======================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "kubectl delete namespace ${KRO_NAMESPACE}"
        return 0
    fi
    
    if kubectl get namespace "${KRO_NAMESPACE}" >/dev/null 2>&1; then
        log_info "Removing namespace: ${KRO_NAMESPACE}"
        if kubectl delete namespace "${KRO_NAMESPACE}" --timeout=120s; then
            log_info "✅ Namespace removed successfully"
        else
            log_warn "⚠️  Failed to remove namespace or timeout occurred"
        fi
    else
        log_warn "Namespace ${KRO_NAMESPACE} not found"
    fi
}

# Remove CRDs (optional)
remove_crds() {
    if [ "$REMOVE_CRDS" != true ]; then
        return 0
    fi
    
    log_info "======================================================"
    log_info "Removing KRO Custom Resource Definitions"
    log_info "======================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "kubectl delete crd -l app.kubernetes.io/name=kro"
        return 0
    fi
    
    local crds
    crds=$(kubectl get crd -o name 2>/dev/null | grep "kro.run" || echo "")
    
    if [ -n "$crds" ]; then
        log_warn "⚠️  This will delete ALL KRO-managed resources!"
        log_warn "⚠️  This action cannot be undone!"
        
        if [ "$FORCE" != true ]; then
            read -p "Are you absolutely sure you want to remove CRDs? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                log_info "Skipping CRD removal"
                return 0
            fi
        fi
        
        log_info "Removing KRO CRDs..."
        echo "$crds" | while read -r crd; do
            if [ -n "$crd" ]; then
                log_info "Removing CRD: $crd"
                kubectl delete "$crd" --timeout=60s || log_warn "Failed to remove $crd"
            fi
        done
        
        log_info "✅ CRD removal completed"
    else
        log_info "No KRO CRDs found to remove"
    fi
}

# Show cleanup results
show_cleanup_results() {
    log_info "======================================================"
    log_info "Cleanup verification"
    log_info "======================================================"
    
    # Check for remaining resources
    local remaining_pods
    remaining_pods=$(kubectl get pods -n "${KRO_NAMESPACE}" 2>/dev/null | wc -l || echo "0")
    
    local remaining_crds
    remaining_crds=$(kubectl get crd 2>/dev/null | grep -c "kro.run" || echo "0")
    
    if [ "$remaining_pods" -eq 0 ] && ([ "$REMOVE_CRDS" != true ] || [ "$remaining_crds" -eq 0 ]); then
        log_info "✅ KRO uninstallation completed successfully"
    else
        log_warn "⚠️  Some resources may still remain:"
        [ "$remaining_pods" -gt 0 ] && log_warn "  - ${remaining_pods} pods in ${KRO_NAMESPACE} namespace"
        [ "$REMOVE_CRDS" = true ] && [ "$remaining_crds" -gt 0 ] && log_warn "  - ${remaining_crds} KRO CRDs"
    fi
    
    if [ "$REMOVE_CRDS" != true ] && [ "$remaining_crds" -gt 0 ]; then
        log_info "ℹ️  ${remaining_crds} KRO CRDs preserved (use --remove-crds to remove)"
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    log_info "Starting KRO uninstallation"
    log_info "Namespace: ${KRO_NAMESPACE}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in DRY-RUN mode"
    fi
    
    check_prerequisites
    show_current_resources
    confirm_action
    
    uninstall_helm_release
    remove_namespace
    remove_crds
    show_cleanup_results
    
    log_info "======================================================"
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN completed - no resources were deleted"
    else
        log_info "KRO uninstallation completed!"
    fi
    log_info "======================================================"
}

main "$@"