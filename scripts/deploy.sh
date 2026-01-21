#!/bin/bash
set -e

# Production EKS Deployment Script
# Usage: ./scripts/deploy.sh [environment] [action]
# Example: ./scripts/deploy.sh prod plan
# Example: ./scripts/deploy.sh prod apply

ENVIRONMENT=${1:-prod}
ACTION=${2:-plan}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please configure them first."
        exit 1
    fi

    log_success "Prerequisites check passed"
}

validate_environment() {
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Valid options: dev, staging, prod"
        exit 1
    fi

    if [[ ! -f "$ROOT_DIR/environments/$ENVIRONMENT/terraform.tfvars" ]]; then
        log_error "Environment configuration file not found: environments/$ENVIRONMENT/terraform.tfvars"
        exit 1
    fi

    log_info "Using environment: $ENVIRONMENT"
}

setup_backend() {
    log_info "Setting up Terraform backend for $ENVIRONMENT..."

    # Check if backend.conf exists for this environment
    if [[ -f "$ROOT_DIR/environments/$ENVIRONMENT/backend.conf" ]]; then
        log_info "Using backend configuration from environments/$ENVIRONMENT/backend.conf"
        
        # Initialize Terraform with backend configuration file
        terraform init \
            -backend-config="$ROOT_DIR/environments/$ENVIRONMENT/backend.conf" \
            -reconfigure
    else
        log_error "Backend configuration file not found: environments/$ENVIRONMENT/backend.conf"
        log_error "Please create this file with the following format:"
        log_error ""
        log_error "key      = \"pipeops-project-iac-${ENVIRONMENT}-terraform.tfstate\""
        log_error "region   = \"us-west-2\""
        log_error "encrypt  = true"
        log_error "dynamodb_table = \"terraform-state-lock-${ENVIRONMENT}\""
        log_error "bucket   = \"pipeops-terraform-state-${ENVIRONMENT}-ACCOUNT_ID\""
        exit 1
    fi
}

terraform_plan() {
    log_info "Running Terraform plan for $ENVIRONMENT..."

    terraform plan \
        -var-file="environments/$ENVIRONMENT/terraform.tfvars" \
        -out="terraform-$ENVIRONMENT.tfplan"

    log_success "Terraform plan completed. Review the plan above."
}

terraform_apply() {
    log_info "Running Terraform apply for $ENVIRONMENT..."

    if [[ ! -f "terraform-$ENVIRONMENT.tfplan" ]]; then
        log_error "Plan file not found. Please run 'plan' first."
        exit 1
    fi

    # Confirmation for production
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        log_warning "You are about to apply changes to PRODUCTION environment!"
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Deployment cancelled."
            exit 0
        fi
    fi

    terraform apply "terraform-$ENVIRONMENT.tfplan"

    log_success "Terraform apply completed!"

    # Clean up plan file
    rm -f "terraform-$ENVIRONMENT.tfplan"
}

configure_kubectl() {
    log_info "Configuring kubectl for the new EKS cluster..."

    CLUSTER_NAME=$(terraform output -raw cluster_name)
    REGION=$(terraform output -raw region || echo "us-west-2")

    aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

    log_success "kubectl configured for cluster: $CLUSTER_NAME"
}

deploy_argocd_apps() {
    log_info "Deploying ArgoCD applications..."

    # Wait for ArgoCD to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

    # Apply the app-of-apps pattern
    kubectl apply -f k8s-manifests/argocd/app-of-apps.yaml

    # Apply sample applications
    kubectl apply -f k8s-manifests/argocd/sample-app.yaml

    log_success "ArgoCD applications deployed"
}

post_deployment() {
    log_info "Running post-deployment steps..."

    # Get important information
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    ARGOCD_PASSWORD=$(terraform output -raw argocd_admin_password)

    log_success "Deployment completed successfully!"
    echo ""
    log_info "=== IMPORTANT INFORMATION ==="
    log_info "Cluster Name: $CLUSTER_NAME"
    log_info "ArgoCD Admin Password: $ARGOCD_PASSWORD"
    echo ""
    log_info "=== NEXT STEPS ==="
    log_info "1. Access ArgoCD UI:"
    log_info "   kubectl port-forward svc/argocd-server -n argocd 8080:80"
    log_info "   Then visit: http://localhost:8080"
    echo ""
    log_info "2. Access Grafana (if monitoring enabled):"
    log_info "   kubectl port-forward svc/grafana -n monitoring 3000:80"
    log_info "   Then visit: http://localhost:3000"
    echo ""
    log_info "3. View all resources:"
    log_info "   kubectl get all --all-namespaces"
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f "terraform-$ENVIRONMENT.tfplan"
}

# Main execution
main() {
    cd "$ROOT_DIR"

    check_prerequisites
    validate_environment

    case "$ACTION" in
        "plan")
            setup_backend
            terraform_plan
            ;;
        "apply")
            setup_backend
            terraform_apply
            configure_kubectl
            deploy_argocd_apps
            post_deployment
            ;;
        "destroy")
            log_warning "You are about to DESTROY the $ENVIRONMENT environment!"
            read -p "Are you sure you want to continue? Type 'destroy' to confirm: " confirm
            if [[ "$confirm" == "destroy" ]]; then
                setup_backend
                terraform destroy -var-file="environments/$ENVIRONMENT/terraform.tfvars"
            else
                log_info "Destroy cancelled."
            fi
            ;;
        *)
            log_error "Invalid action: $ACTION. Valid options: plan, apply, destroy"
            exit 1
            ;;
    esac

    cleanup
}

# Trap to ensure cleanup happens
trap cleanup EXIT

# Run main function
main "$@"