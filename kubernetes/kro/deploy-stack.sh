#!/bin/bash

# Game2048 KRO Stack Deployment Script
# Usage: ./deploy-stack.sh [options]

set -euo pipefail

# Default values
AWS_ACCOUNT_ID=""
ENVIRONMENT="dev"
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --aws-account-id ID    AWS Account ID (required)"
    echo "  --environment ENV      Environment name (dev, staging, prod)"
    echo "  --dry-run             Show what would be deployed without deploying"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --aws-account-id 123456789012 --environment prod"
    echo "  $0 --aws-account-id 123456789012 --dry-run"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --aws-account-id)
                AWS_ACCOUNT_ID="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
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

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local missing_tools=()
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v sed >/dev/null 2>&1 || missing_tools+=("sed")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check kubectl connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check required parameters
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS Account ID is required"
        exit 1
    fi
    
    # Validate AWS Account ID format
    if ! [[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
        log_error "Invalid AWS Account ID format. Must be 12 digits."
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Deploy the merged stack
deploy_stack() {
    log_info "======================================================"
    log_info "Deploying Game2048 Complete Stack"
    log_info "======================================================"
    
    # Create temporary directory for modified files
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Process RGD file
    log_info "Processing ResourceGraphDefinition..."
    local temp_rgd="$temp_dir/game2048-stack-rgd.yaml"
    
    sed -e "s/123456789012/$AWS_ACCOUNT_ID/g" \
        "game2048-stack-rgd.yaml" > "$temp_rgd"
    
    if [ "$DRY_RUN" = true ]; then
        echo "Would deploy ResourceGraphDefinition with:"
        echo "  AWS Account ID: $AWS_ACCOUNT_ID"
        echo "  Environment: $ENVIRONMENT"
        return 0
    fi
    
    # Deploy RGD
    log_info "Deploying ResourceGraphDefinition..."
    if kubectl apply -f "$temp_rgd"; then
        log_info "✅ ResourceGraphDefinition deployed successfully"
    else
        log_error "❌ Failed to deploy ResourceGraphDefinition"
        return 1
    fi
    
    # Wait for RGD to be ready
    log_info "Waiting for ResourceGraphDefinition to be ready..."
    sleep 5
    
    # Process instance file
    log_info "Processing stack instance..."
    local temp_instance="$temp_dir/game2048-stack-instance.yaml"
    
    sed -e "s/123456789012/$AWS_ACCOUNT_ID/g" \
        -e "s/environment: \"prod\"/environment: \"$ENVIRONMENT\"/g" \
        "instances/game2048-stack-instance.yaml" > "$temp_instance"
    
    # Create namespace if it doesn't exist
    kubectl create namespace game-2048 --dry-run=client -o yaml | kubectl apply -f - || true
    
    # Deploy instance
    log_info "Deploying stack instance..."
    if kubectl apply -f "$temp_instance"; then
        log_info "✅ Stack instance deployed successfully"
    else
        log_error "❌ Failed to deploy stack instance"
        return 1
    fi
    
    # Wait for resources to be created
    log_info "Waiting for resources to be created..."
    sleep 15
}

# Show deployment status
show_status() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    log_info "======================================================"
    log_info "Deployment Status"
    log_info "======================================================"
    
    echo ""
    log_info "ResourceGraphDefinition:"
    kubectl get resourcegraphdefinitions -n kro | grep game2048 || true
    
    echo ""
    log_info "Stack Instance:"
    kubectl get game2048stack -n game-2048 || true
    
    echo ""
    log_info "Application Resources:"
    kubectl get all -n game-2048 || true
    
    echo ""
    log_info "AWS Resources:"
    kubectl get tables.dynamodb.services.k8s.aws -n game-2048 || true
    kubectl get buckets.s3.services.k8s.aws -n game-2048 || true
}

# Show next steps
show_next_steps() {
    log_info "======================================================"
    log_info "Next Steps"
    log_info "======================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "This was a dry-run. To actually deploy:"
        log_info "  $0 --aws-account-id $AWS_ACCOUNT_ID --environment $ENVIRONMENT"
        return 0
    fi
    
    echo ""
    log_info "1. Check stack status:"
    echo "   kubectl get game2048stack -n game-2048"
    echo ""
    
    log_info "2. Monitor deployment:"
    echo "   kubectl get all -n game-2048"
    echo ""
    
    log_info "3. Get ingress endpoint:"
    echo "   kubectl get ingress -n game-2048"
    echo ""
    
    log_info "4. Access the game:"
    echo "   Add ingress IP to /etc/hosts as 2048.local"
    echo "   Visit: http://2048.local"
    echo ""
    
    log_warn "Note: Ensure ACK controllers for DynamoDB and S3 are installed!"
}

# Main execution
main() {
    parse_args "$@"
    
    log_info "Starting Game2048 stack deployment"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Environment: $ENVIRONMENT"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in DRY-RUN mode"
    fi
    
    check_prerequisites
    deploy_stack
    show_status
    show_next_steps
    
    log_info "======================================================"
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN completed successfully!"
    else
        log_info "Game2048 stack deployment completed!"
    fi
    log_info "======================================================"
}

main "$@"