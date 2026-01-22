#!/bin/bash

# ====================================================================
# DR Infrastructure Deployment Script
# ====================================================================
# This script manages the deployment of DR infrastructure
# 
# Usage: ./deploy-dr.sh <environment> <action>
# Example: ./deploy-dr.sh prod plan
#          ./deploy-dr.sh prod apply
#          ./deploy-dr.sh prod destroy
# ====================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required arguments are provided
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <environment> <action>"
    print_info "Environments: prod"
    print_info "Actions: plan, apply, destroy, output, refresh"
    print_info "Example: $0 prod plan"
    exit 1
fi

ENVIRONMENT=$1
ACTION=$2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DR_ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Validate environment
if [ "$ENVIRONMENT" != "prod" ]; then
    print_error "DR infrastructure is only supported for 'prod' environment"
    print_info "Provided: $ENVIRONMENT"
    exit 1
fi

# Validate action
VALID_ACTIONS=("plan" "apply" "destroy" "output" "refresh" "validate")
if [[ ! " ${VALID_ACTIONS[@]} " =~ " ${ACTION} " ]]; then
    print_error "Invalid action: $ACTION"
    print_info "Valid actions: ${VALID_ACTIONS[*]}"
    exit 1
fi

# Configuration
BACKEND_CONFIG="$DR_ROOT_DIR/environments/$ENVIRONMENT/backend.conf"
TFVARS_FILE="$DR_ROOT_DIR/environments/$ENVIRONMENT/terraform.tfvars"

echo ""
print_info "========================================="
print_info "DR Infrastructure Deployment"
print_info "========================================="
echo ""
print_info "Environment: $ENVIRONMENT"
print_info "Action: $ACTION"
print_info "Working Directory: $DR_ROOT_DIR"
echo ""

# Change to DR infrastructure directory
cd "$DR_ROOT_DIR"

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if backend config exists
    if [ ! -f "$BACKEND_CONFIG" ]; then
        print_error "Backend configuration not found: $BACKEND_CONFIG"
        print_info "Run setup-dr-prerequisites.sh first:"
        print_info "  ./scripts/setup-dr-prerequisites.sh $ENVIRONMENT us-east-1"
        exit 1
    fi
    
    # Check if tfvars file exists
    if [ ! -f "$TFVARS_FILE" ]; then
        print_error "Terraform variables file not found: $TFVARS_FILE"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        print_error "AWS credentials not configured"
        print_info "Configure AWS CLI with: aws configure"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to initialize Terraform
init_terraform() {
    print_info "Initializing Terraform..."
    
    if [ ! -d ".terraform" ]; then
        terraform init -backend-config="$BACKEND_CONFIG"
        print_success "Terraform initialized"
    else
        print_info "Terraform already initialized (use 'terraform init -reconfigure' to reinitialize)"
    fi
}

# Function to validate Terraform configuration
validate_terraform() {
    print_info "Validating Terraform configuration..."
    terraform validate
    print_success "Terraform configuration is valid"
}

# Function to run terraform plan
run_plan() {
    print_info "Running Terraform plan..."
    terraform plan \
        -var-file="$TFVARS_FILE" \
        -out="tfplan-dr-$ENVIRONMENT"
    
    print_success "Plan completed successfully"
    print_info "Plan saved to: tfplan-dr-$ENVIRONMENT"
    echo ""
    print_warning "Review the plan above before applying"
}

# Function to run terraform apply
run_apply() {
    print_warning "This will create DR infrastructure in the DR region"
    print_info "Estimated cost: ~\$243/month (standby mode)"
    echo ""
    
    if [ -f "tfplan-dr-$ENVIRONMENT" ]; then
        print_info "Applying saved plan: tfplan-dr-$ENVIRONMENT"
        terraform apply "tfplan-dr-$ENVIRONMENT"
    else
        print_info "No saved plan found, running apply with var-file"
        terraform apply -var-file="$TFVARS_FILE"
    fi
    
    print_success "DR infrastructure deployed successfully!"
    echo ""
    print_info "Run 'terraform output' to see DR cluster details"
}

# Function to run terraform destroy
run_destroy() {
    print_error "⚠️  WARNING: This will DESTROY all DR infrastructure!"
    print_warning "This action cannot be undone"
    echo ""
    read -p "Type 'yes' to confirm destruction: " CONFIRM
    
    if [ "$CONFIRM" = "yes" ]; then
        terraform destroy -var-file="$TFVARS_FILE"
        print_success "DR infrastructure destroyed"
    else
        print_info "Destruction cancelled"
        exit 0
    fi
}

# Function to show outputs
show_outputs() {
    print_info "DR Infrastructure Outputs:"
    echo ""
    terraform output
}

# Function to refresh state
refresh_state() {
    print_info "Refreshing Terraform state..."
    terraform refresh -var-file="$TFVARS_FILE"
    print_success "State refreshed"
}

# Main execution
main() {
    check_prerequisites
    init_terraform
    
    case $ACTION in
        plan)
            validate_terraform
            run_plan
            ;;
        apply)
            run_apply
            ;;
        destroy)
            run_destroy
            ;;
        output)
            show_outputs
            ;;
        refresh)
            refresh_state
            ;;
        validate)
            validate_terraform
            ;;
        *)
            print_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac
    
    echo ""
    print_success "========================================="
    print_success "DR Deployment Action Complete"
    print_success "========================================="
    echo ""
    
    if [ "$ACTION" = "apply" ]; then
        print_info "🎯 Next Steps:"
        echo ""
        echo "   1. Configure kubectl for DR cluster:"
        echo "      \$(terraform output -raw dr_kubectl_config_command)"
        echo ""
        echo "   2. Verify DR cluster:"
        echo "      kubectl get nodes"
        echo "      kubectl get namespaces"
        echo ""
        echo "   3. View all outputs:"
        echo "      terraform output"
        echo ""
    fi
}

# Run main function
main
