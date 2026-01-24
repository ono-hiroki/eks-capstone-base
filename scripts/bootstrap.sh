#!/bin/bash
set -euo pipefail

# =============================================================================
# Bootstrap Script (Final Minimized Version)
# =============================================================================
# This script performs the minimum required setup for the EKS cluster.
# Everything else is managed by Argo CD (GitOps).
#
# What this script does:
#   1. Configure kubectl
#   2. Add Helm repositories
#   3. Install AWS Load Balancer Controller
#   4. Install Argo CD
#   5. Apply root-application.yaml (triggers GitOps)
#
# What Argo CD manages automatically:
#   - Istio (base, istiod, gateway)
#   - External Secrets Operator
#   - External DNS (Route 53 automation)
#   - Argo CD Ingress
#   - Istio Ingress (for apps)
#   - demo-app and other applications
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
GITOPS_DIR="${SCRIPT_DIR}/../gitops"

# Check required tools
check_requirements() {
    log_info "Checking requirements..."

    local missing=()
    command -v kubectl &> /dev/null || missing+=("kubectl")
    command -v helm &> /dev/null || missing+=("helm")
    command -v aws &> /dev/null || missing+=("aws")
    command -v terraform &> /dev/null || missing+=("terraform")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    log_info "All required tools are installed"
}

# Get Terraform outputs and export as environment variables
get_terraform_outputs() {
    log_info "Getting Terraform outputs..."

    cd "${TERRAFORM_DIR}"

    export CLUSTER_NAME=$(terraform output -raw cluster_name)
    export AWS_REGION=$(terraform output -raw aws_region)
    export VPC_ID=$(terraform output -raw vpc_id)
    export ALB_CONTROLLER_ROLE_ARN=$(terraform output -raw aws_load_balancer_controller_role_arn)

    # For display only
    export ARGOCD_URL=$(terraform output -raw argocd_url)
    export APP_URL=$(terraform output -raw app_url)

    log_info "Cluster: ${CLUSTER_NAME}"
    log_info "Region: ${AWS_REGION}"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

    log_info "Waiting for nodes to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
}

# Add Helm repositories
add_helm_repos() {
    log_info "Adding Helm repositories..."

    helm repo add eks https://aws.github.io/eks-charts || true
    helm repo add argo https://argoproj.github.io/argo-helm || true

    helm repo update eks argo
}

# Install AWS Load Balancer Controller
install_alb_controller() {
    log_info "Installing AWS Load Balancer Controller..."

    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --namespace kube-system \
        --set clusterName="${CLUSTER_NAME}" \
        --set serviceAccount.create=true \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ALB_CONTROLLER_ROLE_ARN}" \
        --set vpcId="${VPC_ID}" \
        --set region="${AWS_REGION}" \
        --wait

    log_info "Waiting for ALB Controller to be ready..."
    kubectl wait --for=condition=Available deployment/aws-load-balancer-controller \
        -n kube-system --timeout=120s
}

# Install Argo CD
install_argocd() {
    log_info "Installing Argo CD..."

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --set 'server.extraArgs[0]=--insecure' \
        --set server.service.type=ClusterIP \
        --wait

    log_info "Waiting for Argo CD to be ready..."
    kubectl wait --for=condition=Available deployment/argocd-server \
        -n argocd --timeout=180s
}

# Apply root application to start GitOps
apply_root_application() {
    log_info "Applying root application..."

    kubectl apply -f "${GITOPS_DIR}/root-application.yaml"

    log_info "Root application applied. Argo CD will now deploy all infrastructure."
}

# Print summary
print_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Bootstrap completed successfully!${NC}"
    echo "=============================================="
    echo ""
    echo "Argo CD is now deploying:"
    echo "  - Istio (base, istiod, gateway)"
    echo "  - External Secrets Operator"
    echo "  - External DNS"
    echo "  - Ingress resources"
    echo "  - demo-app"
    echo ""
    echo "To access Argo CD immediately (via port-forward):"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "  Open: https://localhost:8080"
    echo ""
    echo "Get Argo CD admin password:"
    echo "  kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d && echo"
    echo ""
    echo "Once External DNS creates Route 53 records:"
    echo "  Argo CD: ${ARGOCD_URL}"
    echo "  App:     ${APP_URL}"
    echo ""
}

# Main
main() {
    log_info "Starting bootstrap..."

    check_requirements
    get_terraform_outputs
    configure_kubectl
    add_helm_repos
    install_alb_controller
    install_argocd
    apply_root_application
    print_summary
}

main "$@"
