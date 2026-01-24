#!/bin/bash
set -euo pipefail

# =============================================================================
# Cleanup Script
# =============================================================================
# This script cleans up resources created by bootstrap.sh and Argo CD.
#
# Cleanup order:
#   1. Delete Argo CD Applications (triggers cascade deletion via finalizers)
#   2. Delete Ingress resources (triggers ALB deletion + External DNS cleanup)
#   3. Wait for ALBs to be deleted
#   4. Uninstall Argo CD (Helm)
#   5. Uninstall AWS Load Balancer Controller (Helm)
#
# What Argo CD finalizers clean up automatically:
#   - Istio (base, istiod, gateway)
#   - External Secrets Operator
#   - External DNS
#   - demo-app and other applications
#
# What External DNS cleans up automatically:
#   - Route 53 records (when Ingress resources are deleted)
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
WAIT_TIMEOUT_SECONDS=300
WAIT_INTERVAL_SECONDS=5

# Get Terraform outputs
get_terraform_outputs() {
    log_info "Getting Terraform outputs..."

    cd "${TERRAFORM_DIR}"

    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "ap-northeast-1")

    if [ -z "${CLUSTER_NAME}" ]; then
        log_warn "Could not get cluster name from Terraform. Some cleanup steps may be skipped."
    fi
}

# Delete Argo CD Applications (this will cascade delete managed resources via finalizers)
delete_argocd_applications() {
    log_info "Deleting Argo CD Applications..."

    # Delete all applications - finalizers will cascade delete child resources
    kubectl delete application --all -n argocd --ignore-not-found=true --wait=false 2>/dev/null || true

    # Wait up to a timeout, but never block forever
    wait_for_argocd_applications
}

# Delete Ingress resources (to trigger ALB deletion and External DNS cleanup)
delete_ingress_resources() {
    log_info "Deleting Ingress resources..."

    # These may already be deleted by Argo CD finalizers, but ensure they're gone
    kubectl delete ingress argocd-server -n argocd --ignore-not-found=true --wait=false 2>/dev/null || true
    kubectl delete ingress istio-gateway -n istio-system --ignore-not-found=true --wait=false 2>/dev/null || true

    wait_for_ingress_deletion
}

# Uninstall Argo CD
uninstall_argocd() {
    log_info "Uninstalling Argo CD..."

    helm uninstall argocd -n argocd 2>/dev/null || true
    kubectl delete namespace argocd --ignore-not-found=true 2>/dev/null || true

    log_info "Argo CD uninstalled"
}

# Uninstall AWS Load Balancer Controller
uninstall_alb_controller() {
    log_info "Uninstalling AWS Load Balancer Controller..."

    helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

    log_info "AWS Load Balancer Controller uninstalled"
}

# Print summary
print_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Cleanup completed!${NC}"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Delete Secrets Manager secret:"
    echo "     aws secretsmanager delete-secret --secret-id demo-app/secrets --force-delete-without-recovery"
    echo ""
    echo "  2. Delete ECR repository:"
    echo "     aws ecr delete-repository --repository-name capstone-demo --force"
    echo ""
    echo "  3. Destroy Terraform resources:"
    echo "     cd ${TERRAFORM_DIR} && terraform destroy"
    echo ""
}

# Main
main() {
    log_info "Starting cleanup..."

    get_terraform_outputs

    # Configure kubectl if cluster exists
    if [ -n "${CLUSTER_NAME}" ]; then
        aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" 2>/dev/null || true
    fi

    delete_argocd_applications
    delete_ingress_resources
    uninstall_argocd
    uninstall_alb_controller

    print_summary
}

wait_for_argocd_applications() {
    log_info "Waiting for Argo CD finalizers (timeout: ${WAIT_TIMEOUT_SECONDS}s)..."

    local start_time
    start_time=$(date +%s)

    while true; do
        if ! kubectl get application -n argocd >/dev/null 2>&1; then
            log_info "argocd namespace not found. Skipping application wait."
            break
        fi

        local remaining
        remaining=$(kubectl get application -n argocd -o name 2>/dev/null | wc -l | tr -d ' ')

        if [ "${remaining}" -eq 0 ]; then
            log_info "Argo CD Applications deleted"
            break
        fi

        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ "${elapsed}" -ge "${WAIT_TIMEOUT_SECONDS}" ]; then
            log_warn "Timeout waiting for Argo CD finalizers. Continuing cleanup."
            break
        fi

        log_info "Waiting for Argo CD Applications to be deleted... (${remaining} remaining)"
        sleep "${WAIT_INTERVAL_SECONDS}"
    done
}

wait_for_ingress_deletion() {
    log_info "Waiting for Ingress deletion (timeout: ${WAIT_TIMEOUT_SECONDS}s)..."

    local start_time
    start_time=$(date +%s)

    while true; do
        local argocd_remaining=0
        local istio_remaining=0

        if kubectl get ingress -n argocd >/dev/null 2>&1; then
            argocd_remaining=$(kubectl get ingress -n argocd -o name 2>/dev/null | wc -l | tr -d ' ')
        fi

        if kubectl get ingress -n istio-system >/dev/null 2>&1; then
            istio_remaining=$(kubectl get ingress -n istio-system -o name 2>/dev/null | wc -l | tr -d ' ')
        fi

        if [ "${argocd_remaining}" -eq 0 ] && [ "${istio_remaining}" -eq 0 ]; then
            log_info "Ingress resources deleted"
            break
        fi

        local now
        now=$(date +%s)
        local elapsed=$((now - start_time))

        if [ "${elapsed}" -ge "${WAIT_TIMEOUT_SECONDS}" ]; then
            log_warn "Timeout waiting for Ingress deletion. Continuing cleanup."
            break
        fi

        log_info "Waiting for Ingress deletion... (argocd=${argocd_remaining}, istio-system=${istio_remaining})"
        sleep "${WAIT_INTERVAL_SECONDS}"
    done
}

main "$@"
