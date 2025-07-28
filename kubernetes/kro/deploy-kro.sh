#!/bin/bash

# KRO Resources Deployment Script
# Usage: ./deploy-kro.sh [options]

set -euo pipefail

# Default values
AWS_ACCOUNT_ID=""
BUCKET_SUFFIX=""
DRY_RUN=false
SKIP_INSTANCES=false

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

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --aws-account-id ID    AWS Account ID (required)"
    echo "  --bucket-suffix SUFFIX Unique suffix for S3 bucket name"
    echo "  --dry-run             Show what would be deployed without deploying"
    echo "  --skip-instances      Only deploy ResourceGraphDefinitions, skip instances"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --aws-account-id 123456789012 --bucket-suffix mycompany"
    echo "  $0 --aws-account-id 123456789012 --dry-run"
    echo "  $0 --aws-account-id 123456789012 --skip-instances"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --aws-account-id)
                AWS_ACCOUNT_ID="$2"
                shift 2
                ;;
            --bucket-suffix)
                BUCKET_SUFFIX="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-instances)
                SKIP_INSTANCES=true
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
        log_info "Please ensure kubectl is configured correctly"
        exit 1
    fi
    
    # Check required parameters
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS Account ID is required"
        log_info "Use --aws-account-id option"
        exit 1
    fi
    
    # Validate AWS Account ID format
    if ! [[ "$AWS_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
        log_error "Invalid AWS Account ID format. Must be 12 digits."
        exit 1
    fi
    
    # Generate bucket suffix if not provided
    if [ -z "$BUCKET_SUFFIX" ]; then
        BUCKET_SUFFIX=$(date +%s | tail -c 6)
        log_info "Generated bucket suffix: $BUCKET_SUFFIX"
    fi
    
    log_info "Prerequisites check passed"
}

# Deploy ResourceGraphDefinitions
deploy_rgds() {
    log_info "======================================================"
    log_info "Deploying ResourceGraphDefinitions"
    log_info "======================================================"
    
    local rgd_files=(
        "dynamodb-rgd.yaml"
        "s3-rgd.yaml"
        "game2048-app-rgd.yaml"
    )
    
    for rgd_file in "${rgd_files[@]}"; do
        log_info "Deploying ResourceGraphDefinition: $rgd_file"
        
        if [ "$DRY_RUN" = true ]; then
            echo "Would deploy: $rgd_file"
            continue
        fi
        
        if kubectl apply -f "$rgd_file"; then
            log_info "✅ Successfully deployed $rgd_file"
        else
            log_error "❌ Failed to deploy $rgd_file"
            return 1
        fi
    done
    
    if [ "$DRY_RUN" != true ]; then
        log_info "Waiting for ResourceGraphDefinitions to be ready..."
        sleep 5
        
        # Check RGD status
        kubectl get resourcegraphdefinitions -n kro
    fi
}

# Deploy instances
deploy_instances() {
    if [ "$SKIP_INSTANCES" = true ]; then
        log_info "Skipping instance deployment as requested"
        return 0
    fi
    
    log_info "======================================================"
    log_info "Deploying Resource Instances"
    log_info "======================================================"
    
    # Create temporary directory for modified files
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Process instance files
    local instance_files=(
        "instances/dynamodb-instance.yaml"
        "instances/s3-instance.yaml"
        "instances/app-instance.yaml"
    )
    
    for instance_file in "${instance_files[@]}"; do
        log_info "Processing instance: $instance_file"
        
        local temp_file="$temp_dir/$(basename "$instance_file")"
        
        # Replace placeholders
        sed -e "s/123456789012/$AWS_ACCOUNT_ID/g" \
            -e "s/unique-suffix/$BUCKET_SUFFIX/g" \
            "$instance_file" > "$temp_file"
        
        if [ "$DRY_RUN" = true ]; then
            echo "Would deploy modified: $instance_file"
            echo "Preview of changes:"
            echo "  AWS Account ID: $AWS_ACCOUNT_ID"
            echo "  Bucket Suffix: $BUCKET_SUFFIX"
            continue
        fi
        
        # Create namespace if it doesn't exist
        kubectl create namespace game-2048 --dry-run=client -o yaml | kubectl apply -f - || true
        
        if kubectl apply -f "$temp_file"; then
            log_info "✅ Successfully deployed $instance_file"
        else
            log_error "❌ Failed to deploy $instance_file"
            return 1
        fi
    done
    
    if [ "$DRY_RUN" != true ]; then
        log_info "Waiting for resources to be created..."
        sleep 10
        
        # Show status
        log_info "Resource status:"
        kubectl get all -n game-2048 || true
    fi
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
    log_info "ResourceGraphDefinitions:"
    kubectl get resourcegraphdefinitions -n kro || true
    
    echo ""
    log_info "Application Resources:"
    kubectl get all -n game-2048 || true
    
    echo ""
    log_info "ConfigMaps and Secrets:"
    kubectl get configmaps,secrets -n game-2048 || true
    
    echo ""
    log_info "Ingress:"
    kubectl get ingress -n game-2048 || true
}

# Show next steps
show_next_steps() {
    log_info "======================================================"
    log_info "Next Steps"
    log_info "======================================================"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "This was a dry-run. To actually deploy:"
        log_info "  $0 --aws-account-id $AWS_ACCOUNT_ID --bucket-suffix $BUCKET_SUFFIX"
        return 0
    fi
    
    echo ""
    log_info "1. Check resource status:"
    echo "   kubectl get all -n game-2048"
    echo ""
    
    log_info "2. Get ingress endpoint:"
    echo "   kubectl get ingress -n game-2048"
    echo ""
    
    log_info "3. Add to /etc/hosts:"
    echo "   echo \"<INGRESS-IP> 2048.local\" >> /etc/hosts"
    echo ""
    
    log_info "4. Access the game:"
    echo "   http://2048.local"
    echo ""
    
    log_info "5. Monitor logs:"
    echo "   kubectl logs -n game-2048 -l app.kubernetes.io/component=backend"
    echo "   kubectl logs -n game-2048 -l app.kubernetes.io/component=frontend"
    echo ""
    
    log_warn "Note: Make sure ACK controllers for DynamoDB and S3 are installed!"
    log_info "Install them with:"
    echo "   ../../../scripts/ack_controller_install.sh dynamodb"
    echo "   ../../../scripts/ack_controller_install.sh s3"
}

# Main execution
main() {
    parse_args "$@"
    
    log_info "Starting KRO resources deployment"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Bucket Suffix: $BUCKET_SUFFIX"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in DRY-RUN mode"
    fi
    
    check_prerequisites
    deploy_rgds
    deploy_instances
    show_status
    show_next_steps
    
    log_info "======================================================"
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN completed successfully!"
    else
        log_info "KRO resources deployment completed!"
    fi
    log_info "======================================================"
}

main "$@"