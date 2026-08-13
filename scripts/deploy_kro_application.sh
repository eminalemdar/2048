#!/bin/bash

# KRO Application Deployment Script
# This script deploys the 2048 game application using KRO in the correct order
#
# Usage: ./deploy_kro_application.sh [cluster-name] [region]
#
# The AWS account ID and the cluster's IAM OIDC provider ID are discovered at
# deploy time and substituted into the instance manifests. Neither is committed
# to the repository: the account ID should not be published, and the OIDC
# provider ID is generated per cluster, so a committed value would be wrong for
# every cluster except the one it came from.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

EKS_CLUSTER_NAME="${1:-${EKS_CLUSTER_NAME:-game2048-dev}}"
AWS_REGION="${2:-${AWS_REGION:-eu-west-1}}"

# Populated by resolve_aws_identity()
AWS_ACCOUNT_ID=""
OIDC_PROVIDER_ID=""

# Directory holding the rendered instance manifests; cleaned up on exit.
RENDER_DIR=""
cleanup_render_dir() {
    if [ -n "$RENDER_DIR" ] && [ -d "$RENDER_DIR" ]; then
        rm -rf "$RENDER_DIR"
    fi
}
trap cleanup_render_dir EXIT

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v curl >/dev/null 2>&1 || missing_tools+=("curl")
    # Needed to resolve the AWS account ID and the cluster's OIDC provider.
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # kro and ACK are EKS Capabilities: they run on AWS-managed infrastructure
    # rather than as pods in this cluster, so the check is for the CRDs the
    # capabilities install, not for controller deployments.

    if ! kubectl get crd resourcegraphdefinitions.kro.run >/dev/null 2>&1; then
        log_error "The kro capability is not active on this cluster."
        log_error "Enable it with 'tofu apply' in opentofu/ (see module.kro in eks.tf),"
        log_error "then wait for the capability to report ACTIVE."
        exit 1
    fi

    # One CRD per ACK service group the RGDs rely on.
    local required_ack_groups=("iam" "dynamodb" "s3")
    for group in "${required_ack_groups[@]}"; do
        if ! kubectl api-resources --api-group="${group}.services.k8s.aws" 2>/dev/null | tail -n +2 | grep -q .; then
            log_error "No ACK CRDs found for '${group}.services.k8s.aws'."
            log_error "Enable the ACK capability with 'tofu apply' in opentofu/ (module.ack in eks.tf)"
            log_error "and wait for it to report ACTIVE before deploying."
            exit 1
        fi
    done

    log_info "Prerequisites check passed"
}

# Wait for RGD to be active
wait_for_rgd() {
    local rgd_name="$1"
    local timeout="${2:-300}"  # 5 minutes default timeout
    local interval=5
    local elapsed=0
    
    log_info "Waiting for RGD '${rgd_name}' to become active..."
    
    while [ $elapsed -lt $timeout ]; do
        # `|| echo "NotFound"` is safe here: on failure kubectl writes nothing to
        # stdout (errors go to /dev/null), so the fallback is the only output.
        local state
        state=$(kubectl get rgd "$rgd_name" -n kro -o jsonpath='{.status.state}' 2>/dev/null || echo "NotFound")
        
        case "$state" in
            "Active")
                log_info "RGD '${rgd_name}' is now active"
                return 0
                ;;
            "NotFound")
                log_warn "RGD '${rgd_name}' not found, waiting..."
                ;;
            "Inactive"|"")
                log_warn "RGD '${rgd_name}' is inactive, waiting..."
                ;;
            *)
                log_warn "RGD '${rgd_name}' state: ${state}, waiting..."
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still waiting for RGD '${rgd_name}' (${elapsed}s elapsed)..."
        fi
    done
    
    log_error "Timeout waiting for RGD '${rgd_name}' to become active"
    return 1
}

# Wait for resource to be ready
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="${4:-300}"
    local interval=5
    local elapsed=0
    
    log_info "Waiting for ${resource_type} '${resource_name}' in namespace '${namespace}' to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1; then
            log_info "${resource_type} '${resource_name}' is ready"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still waiting for ${resource_type} '${resource_name}' (${elapsed}s elapsed)..."
        fi
    done
    
    log_error "Timeout waiting for ${resource_type} '${resource_name}' to be ready"
    return 1
}

# Deploy RGDs
deploy_rgds() {
    log_step "Step 1: Deploying ResourceGraphDefinitions"

    # EKS Auto Mode provides load balancing, but the IngressClass that points at
    # it has to exist before any Ingress referencing "alb" can be reconciled.
    log_info "Applying Auto Mode IngressClass"
    kubectl apply -f kubernetes/auto-mode-ingressclass.yaml

    # The kro capability runs outside the cluster and creates no namespace, so
    # the namespace holding the instances has to be created explicitly.
    log_info "Ensuring the kro namespace exists"
    kubectl apply -f kubernetes/kro/namespace.yaml
    
    local rgds=(
        "kubernetes/kro/iam-rgd.yaml:iam-role-for-service-account"
        "kubernetes/kro/dynamodb-rgd.yaml:dynamodb-table"
        "kubernetes/kro/game-sessions-rgd.yaml:game-sessions-table"
        "kubernetes/kro/s3-rgd.yaml:s3-backup-bucket"
        "kubernetes/kro/game2048-app-rgd.yaml:game2048-application"
    )
    
    for rgd_info in "${rgds[@]}"; do
        local file="${rgd_info%:*}"
        local name="${rgd_info#*:}"
        
        if [ ! -f "$file" ]; then
            log_error "RGD file not found: $file"
            exit 1
        fi
        
        log_info "Applying RGD: $file"
        kubectl apply -f "$file"
        
        # Wait for this RGD to be active before proceeding
        wait_for_rgd "$name"
    done
    
    log_info "All RGDs are now active"
}

# Deploy instances
# Discover the AWS account and the cluster's OIDC provider so the IAM trust
# policy is built for the cluster actually being deployed to.
resolve_aws_identity() {
    log_step "Resolving AWS account and cluster OIDC provider"

    if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null); then
        log_error "Could not determine the AWS account ID. Check your AWS credentials."
        exit 1
    fi

    local issuer
    if ! issuer=$(aws eks describe-cluster \
        --name "$EKS_CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'cluster.identity.oidc.issuer' \
        --output text 2>/dev/null); then
        log_error "Could not read the OIDC issuer for cluster '${EKS_CLUSTER_NAME}' in ${AWS_REGION}."
        log_error "Pass the right name: ./deploy_kro_application.sh <cluster-name> <region>"
        exit 1
    fi

    # The provider ID is the last path segment of the issuer URL, e.g.
    # https://oidc.eks.eu-west-1.amazonaws.com/id/ABCD1234 -> ABCD1234
    OIDC_PROVIDER_ID="${issuer##*/}"

    if [ -z "$OIDC_PROVIDER_ID" ] || [ "$OIDC_PROVIDER_ID" = "None" ]; then
        log_error "Cluster '${EKS_CLUSTER_NAME}' has no OIDC issuer. IRSA requires one."
        exit 1
    fi

    # Only the last four digits are shown; the full account ID stays out of logs.
    log_info "AWS account:   ****${AWS_ACCOUNT_ID: -4}"
    log_info "Cluster:       ${EKS_CLUSTER_NAME} (${AWS_REGION})"
    log_info "OIDC provider: ${OIDC_PROVIDER_ID}"
}

# render_instance writes a copy of an instance manifest with the deployment
# placeholders substituted, and echoes the path to the rendered file.
render_instance() {
    local source_file="$1"

    if [ -z "$RENDER_DIR" ]; then
        RENDER_DIR="$(mktemp -d)"
    fi

    local rendered
    rendered="${RENDER_DIR}/$(basename "$source_file")"

    sed \
        -e "s/__AWS_ACCOUNT_ID__/${AWS_ACCOUNT_ID}/g" \
        -e "s/__OIDC_PROVIDER_ID__/${OIDC_PROVIDER_ID}/g" \
        "$source_file" > "$rendered"

    # Fail loudly rather than applying a manifest with an unresolved value.
    if grep -q "__AWS_ACCOUNT_ID__\|__OIDC_PROVIDER_ID__" "$rendered"; then
        log_error "Unresolved placeholder remains in ${source_file}"
        exit 1
    fi

    echo "$rendered"
}

deploy_instances() {
    log_step "Step 2: Deploying Application Instances"

    # Deploy in dependency order
    local instances=(
        "kubernetes/kro/instances/s3-instance.yaml:s3backupbucket:game2048-backup-dev:kro"
        "kubernetes/kro/instances/game2048-leaderboard-table.yaml:dynamodbtable:game2048-leaderboard-dev:kro"
        "kubernetes/kro/instances/game2048-sessions-table.yaml:gamesessionstable:game2048-sessions-dev:kro"
        "kubernetes/kro/instances/game2048-backend-iam-role.yaml:iamroleforserviceaccount:game2048-backend-iam-role:kro"
        "kubernetes/kro/instances/game2048-app-instance.yaml:game2048application:game2048-dev:kro"
    )
    
    for instance_info in "${instances[@]}"; do
        IFS=':' read -r file resource_type resource_name namespace <<< "$instance_info"
        
        if [ ! -f "$file" ]; then
            log_error "Instance file not found: $file"
            exit 1
        fi
        
        log_info "Applying instance: $file"
        kubectl apply -f "$(render_instance "$file")"
        
        # Wait for this instance to be ready
        wait_for_resource "$resource_type" "$resource_name" "$namespace"
    done
    
    log_info "All instances deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_step "Step 3: Verifying Deployment"
    
    # Check DynamoDB tables
    log_info "Checking DynamoDB tables..."
    # `|| true` rather than `|| echo "0"`: wc has already printed its count by
    # the time a failing kubectl trips `set -o pipefail`, so echoing a fallback
    # would append a second line and break the numeric test below. `true` adds
    # no output. Splitting the assignment from `local` also means the
    # substitution's exit status is no longer masked (SC2155) — hence the
    # explicit fallback, without which `set -e` would abort here.
    local tables
    tables=$(kubectl get table -n kro --no-headers 2>/dev/null | grep -c "" || true)
    if [ "$tables" -ge 2 ]; then
        log_info "✅ DynamoDB tables: $tables found"
        kubectl get table -n kro
    else
        log_warn "⚠️  Expected at least 2 DynamoDB tables, found: $tables"
    fi
    
    # Check S3 bucket
    log_info "Checking S3 bucket..."
    local s3_buckets
    s3_buckets=$(kubectl get bucket -n kro --no-headers 2>/dev/null | grep -c "" || true)
    if [ "$s3_buckets" -ge 1 ]; then
        log_info "✅ S3 bucket: $s3_buckets found"
        kubectl get bucket -n kro
    else
        log_warn "⚠️  Expected at least 1 S3 bucket, found: $s3_buckets"
    fi
    
    # Check IAM role
    log_info "Checking IAM role..."
    if kubectl get role.iam.services.k8s.aws -A --no-headers 2>/dev/null | grep -q "game2048-backend-role"; then
        log_info "✅ IAM role: game2048-backend-role found"
    else
        log_warn "⚠️  IAM role not found"
    fi
    
    # Check application pods
    log_info "Checking application pods..."
    
    if kubectl get namespace game-2048 >/dev/null 2>&1; then
        # Wait for pods to be ready (not just running)
        log_info "Waiting for pods to be ready..."
        
        # Wait for backend pods to be ready
        if kubectl get pods -n game-2048 -l app=game2048-backend --no-headers 2>/dev/null | grep -q .; then
            log_info "Waiting for backend pods to be ready..."
            if kubectl wait --for=condition=Ready pod -l app=game2048-backend -n game-2048 --timeout=300s 2>/dev/null; then
                log_info "✅ Backend pods are ready"
            else
                log_warn "⚠️  Backend pods not ready within timeout"
            fi
        fi
        
        # Wait for frontend pods to be ready
        if kubectl get pods -n game-2048 -l app=game2048-frontend --no-headers 2>/dev/null | grep -q .; then
            log_info "Waiting for frontend pods to be ready..."
            if kubectl wait --for=condition=Ready pod -l app=game2048-frontend -n game-2048 --timeout=300s 2>/dev/null; then
                log_info "✅ Frontend pods are ready"
            else
                log_warn "⚠️  Frontend pods not ready within timeout"
            fi
        fi
        
        # Show final pod status
        # `grep -c` already prints 0 when nothing matches, and then exits 1. The
        # previous `|| echo "0"` appended a SECOND zero, so pods_ready became
        # "0\n0" and the `-ge` test below failed with "integer expression
        # expected" — precisely when no pods were ready, i.e. the failure this
        # check exists to report. `|| true` swallows the status without output.
        # Column order is NAME, READY (1/1), STATUS (Running) — the ready count
        # comes FIRST. The pattern used to be "Running.*1/1", which can never
        # match that layout, so this reported 0 ready pods on every successful
        # deployment. Match the real order instead.
        local pods_ready
        pods_ready=$(kubectl get pods -n game-2048 --no-headers 2>/dev/null | grep -c "1/1.*Running\|2/2.*Running" || true)
        # `grep -c ""` counts lines like `wc -l` but without the leading padding
        # BSD wc emits, which showed up in the message below as "0/       4".
        local pods_total
        pods_total=$(kubectl get pods -n game-2048 --no-headers 2>/dev/null | grep -c "" || true)
        
        if [ "$pods_ready" -ge 4 ]; then
            log_info "✅ Application pods: $pods_ready/$pods_total ready"
        else
            log_warn "⚠️  Expected at least 4 ready pods, found: $pods_ready/$pods_total"
        fi
        
        kubectl get pods -n game-2048
    else
        log_warn "⚠️  Application namespace 'game-2048' not found"
    fi
    
    # Check ingress and ALB health
    log_info "Checking ingress and ALB health..."
    if kubectl get ingress -n game-2048 --no-headers 2>/dev/null | grep -q "game2048-ingress"; then
        log_info "Waiting for ALB to be provisioned..."
        
        local alb_url=""
        local timeout=300  # 5 minutes for ALB provisioning
        local interval=10
        local elapsed=0
        
        # Wait for ALB URL to be available
        while [ $elapsed -lt $timeout ]; do
            alb_url=$(kubectl get ingress game2048-ingress -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
            
            if [ -n "$alb_url" ] && [ "$alb_url" != "null" ]; then
                log_info "✅ ALB URL available: $alb_url"
                break
            fi
            
            sleep $interval
            elapsed=$((elapsed + interval))
            
            if [ $((elapsed % 60)) -eq 0 ]; then
                log_info "Still waiting for ALB provisioning (${elapsed}s elapsed)..."
            fi
        done
        
        if [ -n "$alb_url" ] && [ "$alb_url" != "null" ]; then
            # Test ALB health
            log_info "Testing ALB health..."
            local health_timeout=120  # 2 minutes for ALB to be healthy
            local health_elapsed=0
            local alb_healthy=false
            
            while [ $health_elapsed -lt $health_timeout ]; do
                if curl -s --max-time 10 "http://$alb_url" >/dev/null 2>&1; then
                    log_info "✅ ALB is healthy and responding"
                    alb_healthy=true
                    break
                fi
                
                sleep 15
                health_elapsed=$((health_elapsed + 15))
                
                if [ $((health_elapsed % 45)) -eq 0 ]; then
                    log_info "Still waiting for ALB to be healthy (${health_elapsed}s elapsed)..."
                fi
            done
            
            if [ "$alb_healthy" = true ]; then
                echo "   🌐 Application URL: http://$alb_url"
                log_info "✅ ALB is fully operational"
            else
                log_warn "⚠️  ALB is provisioned but not yet responding to requests"
                echo "   🌐 Application URL: http://$alb_url (may need a few more minutes)"
            fi
        else
            log_warn "⚠️  ALB URL not available within timeout"
        fi
    else
        log_warn "⚠️  Ingress not found"
    fi
}

# Main deployment function
main() {
    log_info "======================================================"
    log_info "Starting KRO Application Deployment"
    log_info "======================================================"
    
    check_prerequisites
    resolve_aws_identity
    deploy_rgds
    deploy_instances
    verify_deployment
    
    log_info "======================================================"
    log_info "🎉 Deployment completed successfully!"
    log_info "======================================================"
    
    # Final instructions
    echo ""
    log_info "Next steps:"
    echo "1. Wait a few minutes for the ALB to be fully provisioned"
    echo "2. Test the application health endpoint:"
    echo "   curl http://\$(kubectl get ingress game2048-ingress -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
    echo "3. Access the game in your browser using the ALB URL above"
    echo ""
    log_info "To check deployment status:"
    echo "   kubectl get pods -n game-2048"
    echo "   kubectl get table -n kro"
    echo "   kubectl get bucket -n kro"
    echo "   kubectl get ingress -n game-2048"
}

# Run main function
main "$@"