#!/bin/bash

# ACK Controller Cleanup Script
# Usage: ./ack_controller_cleanup.sh <service> [cluster-name] [region]

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Input validation
if [ $# -lt 1 ]; then
    echo "Usage: $0 <service> [cluster-name] [region]"
    echo "Example: $0 dynamodb game2048-dev-cluster eu-west-1"
    echo ""
    echo "Available services: dynamodb, s3, rds, ec2, iam, etc."
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmation prompts"
    exit 1
fi

declare SERVICE="$1"
declare EKS_CLUSTER_NAME="${2:-game2048-dev-cluster}"
declare AWS_REGION="${3:-eu-west-1}"
declare ACK_SYSTEM_NAMESPACE="ack-system"

# Parse additional options
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
    esac
done

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

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_error "EKS cluster '${EKS_CLUSTER_NAME}' not found in region '${AWS_REGION}'"
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
    log_warn "This will remove the following resources:"
    echo "  - Helm release: ack-${SERVICE}-controller"
    echo "  - IAM role: ack-${SERVICE}-controller-${EKS_CLUSTER_NAME}"
    echo "  - All attached IAM policies"
    echo "  - Service account annotations"
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

# Remove Helm release
remove_helm_release() {
    log_info "======================================================"
    log_info "Removing Helm release"
    log_info "======================================================"
    
    local RELEASE_NAME="ack-${SERVICE}-controller"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "helm uninstall ${RELEASE_NAME} -n ${ACK_SYSTEM_NAMESPACE}"
        return 0
    fi
    
    # Check if release exists
    if helm list -n "${ACK_SYSTEM_NAMESPACE}" | grep -q "${RELEASE_NAME}"; then
        log_info "Uninstalling Helm release: ${RELEASE_NAME}"
        if helm uninstall "${RELEASE_NAME}" -n "${ACK_SYSTEM_NAMESPACE}"; then
            log_info "Successfully removed Helm release"
        else
            log_error "Failed to remove Helm release"
            return 1
        fi
    else
        log_warn "Helm release ${RELEASE_NAME} not found"
    fi
    
    # Wait for pods to be terminated
    log_info "Waiting for pods to be terminated..."
    kubectl wait --for=delete pods -l "app.kubernetes.io/name=ack-${SERVICE}-controller" -n "${ACK_SYSTEM_NAMESPACE}" --timeout=120s || log_warn "Timeout waiting for pods to terminate"
}

# Remove IAM resources
remove_iam_resources() {
    log_info "======================================================"
    log_info "Removing IAM resources"
    log_info "======================================================"
    
    local ACK_CONTROLLER_IAM_ROLE="ack-${SERVICE}-controller-${EKS_CLUSTER_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Remove IAM role: ${ACK_CONTROLLER_IAM_ROLE}"
        log_dry_run "Detach all managed policies"
        log_dry_run "Delete inline policies"
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "${ACK_CONTROLLER_IAM_ROLE}" >/dev/null 2>&1; then
        log_warn "IAM role ${ACK_CONTROLLER_IAM_ROLE} not found"
        return 0
    fi
    
    log_info "Found IAM role: ${ACK_CONTROLLER_IAM_ROLE}"
    
    # Detach managed policies
    log_info "Detaching managed policies..."
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "${ACK_CONTROLLER_IAM_ROLE}" --query 'AttachedPolicies[].PolicyArn' --output text)
    
    if [ -n "$attached_policies" ]; then
        for policy_arn in $attached_policies; do
            log_info "Detaching policy: ${policy_arn}"
            aws iam detach-role-policy --role-name "${ACK_CONTROLLER_IAM_ROLE}" --policy-arn "${policy_arn}" || log_warn "Failed to detach ${policy_arn}"
        done
    else
        log_info "No managed policies attached"
    fi
    
    # Delete inline policies
    log_info "Removing inline policies..."
    local inline_policies
    inline_policies=$(aws iam list-role-policies --role-name "${ACK_CONTROLLER_IAM_ROLE}" --query 'PolicyNames' --output text)
    
    if [ -n "$inline_policies" ] && [ "$inline_policies" != "None" ]; then
        for policy_name in $inline_policies; do
            log_info "Deleting inline policy: ${policy_name}"
            aws iam delete-role-policy --role-name "${ACK_CONTROLLER_IAM_ROLE}" --policy-name "${policy_name}" || log_warn "Failed to delete ${policy_name}"
        done
    else
        log_info "No inline policies found"
    fi
    
    # Delete the role
    log_info "Deleting IAM role: ${ACK_CONTROLLER_IAM_ROLE}"
    if aws iam delete-role --role-name "${ACK_CONTROLLER_IAM_ROLE}"; then
        log_info "Successfully deleted IAM role"
    else
        log_error "Failed to delete IAM role"
        return 1
    fi
}

# Clean up namespace if empty
cleanup_namespace() {
    log_info "======================================================"
    log_info "Checking namespace cleanup"
    log_info "======================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_dry_run "Check if namespace ${ACK_SYSTEM_NAMESPACE} can be deleted"
        return 0
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "${ACK_SYSTEM_NAMESPACE}" >/dev/null 2>&1; then
        log_info "Namespace ${ACK_SYSTEM_NAMESPACE} does not exist"
        return 0
    fi
    
    # Check if there are other ACK controllers in the namespace
    local other_controllers
    other_controllers=$(kubectl get deployments -n "${ACK_SYSTEM_NAMESPACE}" --no-headers 2>/dev/null | grep -v "ack-${SERVICE}-controller" | wc -l)
    
    if [ "$other_controllers" -eq 0 ]; then
        log_info "No other ACK controllers found in namespace"
        read -p "Delete the ${ACK_SYSTEM_NAMESPACE} namespace? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Deleting namespace: ${ACK_SYSTEM_NAMESPACE}"
            kubectl delete namespace "${ACK_SYSTEM_NAMESPACE}" || log_warn "Failed to delete namespace"
        fi
    else
        log_info "Found ${other_controllers} other ACK controllers, keeping namespace"
    fi
}

# Show remaining resources
show_remaining_resources() {
    log_info "======================================================"
    log_info "Checking for remaining resources"
    log_info "======================================================"
    
    # Check for any remaining ACK resources
    log_info "Checking for remaining ${SERVICE} resources..."
    
    # Check CRDs
    local crds
    crds=$(kubectl get crd 2>/dev/null | grep "${SERVICE}.services.k8s.aws" | wc -l || echo "0")
    if [ "$crds" -gt 0 ]; then
        log_warn "Found ${crds} CRDs for ${SERVICE} service"
        kubectl get crd | grep "${SERVICE}.services.k8s.aws" || true
    fi
    
    # Check for any resources created by the controller
    log_info "Checking for ${SERVICE} custom resources..."
    kubectl api-resources --api-group="${SERVICE}.services.k8s.aws" 2>/dev/null | tail -n +2 | while read -r line; do
        if [ -n "$line" ]; then
            local resource_type
            resource_type=$(echo "$line" | awk '{print $1}')
            local count
            count=$(kubectl get "$resource_type" --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$count" -gt 0 ]; then
                log_warn "Found ${count} ${resource_type} resources"
            fi
        fi
    done || log_info "No custom resources found"
}

# Main execution
main() {
    log_info "Starting ACK ${SERVICE} controller cleanup"
    log_info "Cluster: ${EKS_CLUSTER_NAME}"
    log_info "Region: ${AWS_REGION}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in DRY-RUN mode"
    fi
    
    check_prerequisites
    confirm_action
    
    remove_helm_release
    remove_iam_resources
    cleanup_namespace
    show_remaining_resources
    
    log_info "======================================================"
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN completed - no resources were deleted"
    else
        log_info "ACK ${SERVICE} controller cleanup completed!"
    fi
    log_info "======================================================"
}

main "$@"