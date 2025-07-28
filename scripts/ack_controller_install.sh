#!/bin/bash

# Improved ACK Controller Installation Script
# Usage: ./ack_controller_install_fixed.sh <service> <cluster-name> <region>

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Input validation
if [ $# -lt 1 ]; then
    echo "Usage: $0 <service> [cluster-name] [region]"
    echo "Example: $0 dynamodb game2048-dev-cluster eu-west-1"
    exit 1
fi

declare SERVICE="$1"
declare EKS_CLUSTER_NAME="${2:-game2048-dev-cluster}"
declare AWS_REGION="${3:-eu-west-1}"
declare ACK_SYSTEM_NAMESPACE="ack-system"

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

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws")
    command -v helm >/dev/null 2>&1 || missing_tools+=("helm")
    command -v kubectl >/dev/null 2>&1 || missing_tools+=("kubectl")
    command -v eksctl >/dev/null 2>&1 || missing_tools+=("eksctl")
    
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

install() {
    log_info "======================================================"
    log_info "Installing ACK ${SERVICE} Controller"
    log_info "======================================================"
    
    # Get latest release version
    log_info "Getting latest release version..."
    local RELEASE_VERSION
    RELEASE_VERSION=$(curl -sL "https://api.github.com/repos/aws-controllers-k8s/${SERVICE}-controller/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
    
    if [ -z "$RELEASE_VERSION" ]; then
        log_error "Failed to get release version for ${SERVICE} controller"
        exit 1
    fi
    
    log_info "Using release version: ${RELEASE_VERSION}"
    
    local CHART_REPO="public.ecr.aws/aws-controllers-k8s/${SERVICE}-chart"
    
    log_info "Logging into ECR Public registry..."
    # ECR Public is always in us-east-1 regardless of your cluster region
    if ! aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws; then
        log_error "Failed to login to ECR Public registry"
        exit 1
    fi
    
    log_info "Installing Helm chart..."
    if helm install --create-namespace --namespace "${ACK_SYSTEM_NAMESPACE}" "ack-${SERVICE}-controller" \
        --set "aws.region=${AWS_REGION}" \
        "oci://${CHART_REPO}" \
        --version "${RELEASE_VERSION}"; then
        log_info "Successfully installed ACK ${SERVICE} controller"
    else
        log_error "Failed to install ACK ${SERVICE} controller"
        exit 1
    fi
}

permissions() {
    log_info "======================================================"
    log_info "Setting up IRSA and IAM permissions"
    log_info "======================================================"
    
    # Create temporary directory for files
    local TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf ${TEMP_DIR}" EXIT
    
    log_info "Associating OIDC provider with cluster..."
    if ! eksctl utils associate-iam-oidc-provider --cluster "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --approve; then
        log_warn "OIDC provider association failed (might already exist)"
    fi
    
    # Get AWS account and OIDC provider info
    local AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
    
    local OIDC_PROVIDER
    OIDC_PROVIDER=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
    
    local ACK_K8S_SERVICE_ACCOUNT_NAME="ack-${SERVICE}-controller"
    local ACK_CONTROLLER_IAM_ROLE="ack-${SERVICE}-controller-${EKS_CLUSTER_NAME}"
    
    # Create trust policy
    cat > "${TEMP_DIR}/trust.json" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "${OIDC_PROVIDER}:sub": "system:serviceaccount:${ACK_SYSTEM_NAMESPACE}:${ACK_K8S_SERVICE_ACCOUNT_NAME}"
                }
            }
        }
    ]
}
EOF
    
    log_info "Creating IAM role: ${ACK_CONTROLLER_IAM_ROLE}"
    local ACK_CONTROLLER_IAM_ROLE_DESCRIPTION="IRSA role for ACK ${SERVICE} controller deployment on EKS cluster ${EKS_CLUSTER_NAME}"
    
    # Check if role already exists
    if aws iam get-role --role-name "${ACK_CONTROLLER_IAM_ROLE}" >/dev/null 2>&1; then
        log_warn "IAM role ${ACK_CONTROLLER_IAM_ROLE} already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "${ACK_CONTROLLER_IAM_ROLE}" \
            --assume-role-policy-document "file://${TEMP_DIR}/trust.json" \
            --description "${ACK_CONTROLLER_IAM_ROLE_DESCRIPTION}"
    fi
    
    local ACK_CONTROLLER_IAM_ROLE_ARN
    ACK_CONTROLLER_IAM_ROLE_ARN=$(aws iam get-role --role-name="${ACK_CONTROLLER_IAM_ROLE}" --query Role.Arn --output text)
    
    log_info "Attaching policies to IAM role..."
    
    # Get recommended policies
    local BASE_URL="https://raw.githubusercontent.com/aws-controllers-k8s/${SERVICE}-controller/main"
    local POLICY_ARN_URL="${BASE_URL}/config/iam/recommended-policy-arn"
    local INLINE_POLICY_URL="${BASE_URL}/config/iam/recommended-inline-policy"
    
    # Download and attach managed policies
    if curl -sL "${POLICY_ARN_URL}" -o "${TEMP_DIR}/policy-arns.txt"; then
        while IFS= read -r POLICY_ARN; do
            if [ -n "$POLICY_ARN" ]; then
                log_info "Attaching policy: ${POLICY_ARN}"
                aws iam attach-role-policy \
                    --role-name "${ACK_CONTROLLER_IAM_ROLE}" \
                    --policy-arn "${POLICY_ARN}" || log_warn "Failed to attach ${POLICY_ARN}"
            fi
        done < "${TEMP_DIR}/policy-arns.txt"
    else
        log_warn "Could not download recommended policy ARNs"
    fi
    
    # Download and attach inline policy if exists
    if curl -sL "${INLINE_POLICY_URL}" -o "${TEMP_DIR}/inline-policy.json" && [ -s "${TEMP_DIR}/inline-policy.json" ]; then
        log_info "Attaching inline policy..."
        aws iam put-role-policy \
            --role-name "${ACK_CONTROLLER_IAM_ROLE}" \
            --policy-name "ack-recommended-policy" \
            --policy-document "file://${TEMP_DIR}/inline-policy.json" || log_warn "Failed to attach inline policy"
    fi
    
    log_info "Annotating service account with IAM role..."
    kubectl annotate serviceaccount -n "${ACK_SYSTEM_NAMESPACE}" "${ACK_K8S_SERVICE_ACCOUNT_NAME}" \
        "eks.amazonaws.com/role-arn=${ACK_CONTROLLER_IAM_ROLE_ARN}" --overwrite
    
    # Restart deployment to pick up new role
    local ACK_DEPLOYMENT_NAME
    ACK_DEPLOYMENT_NAME=$(kubectl get deployments -n "${ACK_SYSTEM_NAMESPACE}" --no-headers | grep "${SERVICE}" | awk '{print $1}')
    
    if [ -n "$ACK_DEPLOYMENT_NAME" ]; then
        log_info "Restarting deployment: ${ACK_DEPLOYMENT_NAME}"
        kubectl -n "${ACK_SYSTEM_NAMESPACE}" rollout restart deployment "${ACK_DEPLOYMENT_NAME}"
        kubectl -n "${ACK_SYSTEM_NAMESPACE}" rollout status deployment "${ACK_DEPLOYMENT_NAME}" --timeout=300s
    else
        log_warn "Could not find deployment for ${SERVICE} controller"
    fi
}

# Main execution
main() {
    log_info "Starting ACK ${SERVICE} controller installation"
    log_info "Cluster: ${EKS_CLUSTER_NAME}"
    log_info "Region: ${AWS_REGION}"
    
    check_prerequisites
    install
    permissions
    
    log_info "======================================================"
    log_info "ACK ${SERVICE} controller installation completed!"
    log_info "======================================================"
    
    # Show status
    kubectl get pods -n "${ACK_SYSTEM_NAMESPACE}" -l "app.kubernetes.io/name=ack-${SERVICE}-controller"
}

main "$@"