#!/bin/bash

# KRO Application Cleanup Script
# This script removes the 2048 game application deployed with KRO in the correct order
# Usage: ./cleanup_kro_application.sh [--force]

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse command line arguments
FORCE=false
for arg in "$@"; do
    case $arg in
        --force)
            FORCE=true
            shift
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Usage: $0 [--force]"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Confirm cleanup
confirm_cleanup() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo ""
    log_warn "This will remove the following resources:"
    echo "  - Game2048 application (pods, services, ingress)"
    echo "  - IAM role for backend service account"
    echo "  - DynamoDB tables (leaderboard and game sessions)"
    echo "  - S3 backup bucket"
    echo "  - All ResourceGraphDefinitions"
    echo "  - Application namespace (game-2048)"
    echo ""
    log_warn "⚠️  This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

# Wait for resource to be deleted
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="${4:-120}"
    local interval=5
    local elapsed=0
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted..."
    
    while [ $elapsed -lt $timeout ]; do
        if ! kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1; then
            log_info "${resource_type} '${resource_name}' deleted successfully"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still waiting for ${resource_type} '${resource_name}' deletion (${elapsed}s elapsed)..."
        fi
    done
    
    log_warn "Timeout waiting for ${resource_type} '${resource_name}' to be deleted (continuing anyway)"
    return 1
}

# Remove instances
remove_instances() {
    log_step "Step 1: Removing Application Instances"
    
    # Remove in reverse dependency order
    local instances=(
        "kubernetes/kro/instances/game2048-app-instance.yaml:game2048application:game2048-dev:kro"
        "kubernetes/kro/instances/game2048-backend-iam-role.yaml:iamroleforserviceaccount:game2048-backend-iam-role:kro"
        "kubernetes/kro/instances/game2048-sessions-table.yaml:gamesessionstable:game2048-sessions-dev:kro"
        "kubernetes/kro/instances/game2048-leaderboard-table.yaml:dynamodbtable:game2048-leaderboard-dev:kro"
        "kubernetes/kro/instances/s3-instance.yaml:s3backupbucket:game2048-backup-dev:kro"
    )
    
    for instance_info in "${instances[@]}"; do
        IFS=':' read -r file resource_type resource_name namespace <<< "$instance_info"
        
        if [ -f "$file" ]; then
            log_info "Removing instance: $file"
            kubectl delete -f "$file" --ignore-not-found=true
            
            # Wait for deletion to complete for critical resources
            if [[ "$resource_type" == "game2048application" ]]; then
                wait_for_deletion "$resource_type" "$resource_name" "$namespace" 180
            fi
        else
            log_warn "Instance file not found: $file (skipping)"
        fi
    done
    
    log_info "All instances removed"
}

# Remove RGDs
remove_rgds() {
    log_step "Step 2: Removing ResourceGraphDefinitions"
    
    local rgds=(
        "kubernetes/kro/game2048-app-rgd.yaml"
        "kubernetes/kro/s3-rgd.yaml"
        "kubernetes/kro/iam-rgd.yaml"
        "kubernetes/kro/game-sessions-rgd.yaml"
        "kubernetes/kro/dynamodb-rgd.yaml"
    )
    
    for file in "${rgds[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing RGD: $file"
            kubectl delete -f "$file" --ignore-not-found=true
        else
            log_warn "RGD file not found: $file (skipping)"
        fi
    done
    
    log_info "All RGDs removed"
}

# Clean up namespace
cleanup_namespace() {
    log_step "Step 3: Cleaning up Namespace"
    
    if kubectl get namespace game-2048 >/dev/null 2>&1; then
        log_info "Removing namespace: game-2048"
        kubectl delete namespace game-2048 --ignore-not-found=true
        wait_for_deletion "namespace" "game-2048" "" 120
    else
        log_info "Namespace 'game-2048' not found (already cleaned up)"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_step "Step 4: Verifying Cleanup"
    
    local cleanup_issues=()
    
    # Check namespace
    if kubectl get namespace game-2048 >/dev/null 2>&1; then
        cleanup_issues+=("Namespace 'game-2048' still exists")
    else
        log_info "✅ Namespace 'game-2048' removed"
    fi
    
    # Check DynamoDB tables
    local tables=$(kubectl get table -n kro --no-headers 2>/dev/null | grep -E "game2048-(leaderboard|sessions)-dev" | wc -l || echo "0")
    if [ "$tables" -eq 0 ]; then
        log_info "✅ DynamoDB tables removed"
    else
        cleanup_issues+=("$tables DynamoDB tables still exist")
    fi
    
    # Check S3 buckets
    local buckets=$(kubectl get bucket -n kro --no-headers 2>/dev/null | grep "game2048-backup-dev" | wc -l || echo "0")
    if [ "$buckets" -eq 0 ]; then
        log_info "✅ S3 buckets removed"
    else
        cleanup_issues+=("$buckets S3 buckets still exist")
    fi
    
    # Check IAM roles
    local iam_roles=$(kubectl get role.iam.services.k8s.aws -A --no-headers 2>/dev/null | grep "game2048-backend-role" | wc -l || echo "0")
    if [ "$iam_roles" -eq 0 ]; then
        log_info "✅ IAM roles removed"
    else
        cleanup_issues+=("$iam_roles IAM roles still exist")
    fi
    
    # Check RGDs
    local rgds=$(kubectl get rgd -n kro --no-headers 2>/dev/null | grep -E "(iam-role-for-service-account|dynamodb-table|game-sessions-table|s3-backup-bucket|game2048-application)" | wc -l || echo "0")
    if [ "$rgds" -eq 0 ]; then
        log_info "✅ ResourceGraphDefinitions removed"
    else
        cleanup_issues+=("$rgds ResourceGraphDefinitions still exist")
    fi
    
    # Report results
    if [ ${#cleanup_issues[@]} -eq 0 ]; then
        log_info "✅ Cleanup completed successfully - no issues found"
    else
        log_warn "⚠️  Cleanup completed with some issues:"
        for issue in "${cleanup_issues[@]}"; do
            echo "   - $issue"
        done
        echo ""
        log_info "You may need to manually clean up remaining resources"
    fi
}

# Main cleanup function
main() {
    log_info "======================================================"
    log_info "Starting KRO Application Cleanup"
    log_info "======================================================"
    
    check_prerequisites
    confirm_cleanup
    remove_instances
    remove_rgds
    cleanup_namespace
    verify_cleanup
    
    log_info "======================================================"
    log_info "🧹 Cleanup completed!"
    log_info "======================================================"
    
    echo ""
    log_info "The 2048 game application has been removed from your cluster."
    log_info "KRO and ACK controllers are still installed and can be reused."
    echo ""
    log_info "To completely remove KRO and ACK controllers:"
    echo "   ./scripts/kro_uninstall.sh"
    echo "   ./scripts/ack_controller_cleanup.sh iam <cluster-name> <region>"
    echo "   ./scripts/ack_controller_cleanup.sh dynamodb <cluster-name> <region>"
    echo "   ./scripts/ack_controller_cleanup.sh s3 <cluster-name> <region>"
}

# Run main function
main "$@"