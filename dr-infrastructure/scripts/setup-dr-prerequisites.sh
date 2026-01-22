#!/bin/bash

# ====================================================================
# DR Infrastructure Prerequisites Setup Script
# ====================================================================
# This script sets up AWS resources required for DR Terraform state management
# 
# Usage: ./setup-dr-prerequisites.sh <environment> <dr-region>
# Example: ./setup-dr-prerequisites.sh prod us-east-1
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
    print_error "Usage: $0 <environment> <dr-region>"
    print_info "Example: $0 prod us-east-1"
    exit 1
fi

ENVIRONMENT=$1
DR_REGION=$2
PROJECT_NAME=${PROJECT_NAME:-pipeops}  # Can be overridden via environment variable

# Get AWS Account ID
print_info "Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS Account ID: $ACCOUNT_ID"

# Define resource names
BUCKET_NAME="${PROJECT_NAME}-terraform-state-dr-${ACCOUNT_ID}"
DYNAMODB_TABLE="terraform-state-lock-dr"
KMS_ALIAS="alias/${PROJECT_NAME}-terraform-state-dr"

echo ""
print_info "========================================="
print_info "DR Infrastructure Prerequisites Setup"
print_info "========================================="
echo ""
print_info "Environment: $ENVIRONMENT"
print_info "DR Region: $DR_REGION"
print_info "S3 Bucket: $BUCKET_NAME"
print_info "DynamoDB Table: $DYNAMODB_TABLE"
print_info "KMS Key Alias: $KMS_ALIAS"
echo ""

# Function to create S3 bucket for Terraform state
create_s3_bucket() {
    print_info "Creating S3 bucket for DR Terraform state..."
    
    if aws s3 ls "s3://${BUCKET_NAME}" 2>&1 | grep -q 'NoSuchBucket'; then
        # Create bucket
        if [ "$DR_REGION" = "us-east-1" ]; then
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$DR_REGION"
        else
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$DR_REGION" \
                --create-bucket-configuration LocationConstraint="$DR_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$BUCKET_NAME" \
            --versioning-configuration Status=Enabled \
            --region "$DR_REGION"
        
        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "$BUCKET_NAME" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }' \
            --region "$DR_REGION"
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$BUCKET_NAME" \
            --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
            --region "$DR_REGION"
        
        print_success "S3 bucket created: $BUCKET_NAME"
    else
        print_warning "S3 bucket already exists: $BUCKET_NAME"
    fi
}

# Function to create DynamoDB table for state locking
create_dynamodb_table() {
    print_info "Creating DynamoDB table for DR state locking..."
    
    if ! aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$DR_REGION" &>/dev/null; then
        aws dynamodb create-table \
            --table-name "$DYNAMODB_TABLE" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$DR_REGION" \
            --tags Key=Project,Value="$PROJECT_NAME" \
                   Key=Environment,Value="$ENVIRONMENT-dr" \
                   Key=ManagedBy,Value=terraform \
                   Key=DisasterRecovery,Value=true \
                   Key=Workspace,Value=dr
        
        print_info "Waiting for DynamoDB table to be active..."
        aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$DR_REGION"
        
        print_success "DynamoDB table created: $DYNAMODB_TABLE"
    else
        print_warning "DynamoDB table already exists: $DYNAMODB_TABLE"
    fi
}

# Function to generate backend configuration
generate_backend_config() {
    print_info "Generating backend configuration..."
    
    BACKEND_CONFIG_DIR="environments/${ENVIRONMENT}"
    mkdir -p "$BACKEND_CONFIG_DIR"
    
    cat > "$BACKEND_CONFIG_DIR/backend.conf" <<EOF
bucket         = "${BUCKET_NAME}"
key            = "pipeops-project-iac-dr-terraform.tfstate"
region         = "${DR_REGION}"
encrypt        = true
dynamodb_table = "${DYNAMODB_TABLE}"
EOF
    
    print_success "Backend configuration generated: $BACKEND_CONFIG_DIR/backend.conf"
}

# Function to print next steps
print_next_steps() {
    echo ""
    print_success "========================================="
    print_success "DR Prerequisites Setup Complete!"
    print_success "========================================="
    echo ""
    print_info "📋 Resources Created:"
    echo "   • S3 Bucket: $BUCKET_NAME"
    echo "   • DynamoDB Table: $DYNAMODB_TABLE"
    echo "   • Backend Config: environments/${ENVIRONMENT}/backend.conf"
    echo ""
    print_info "🚀 Next Steps:"
    echo ""
    echo "   1. Initialize Terraform:"
    echo "      cd dr-infrastructure"
    echo "      terraform init -backend-config=environments/${ENVIRONMENT}/backend.conf"
    echo ""
    echo "   2. Plan the DR deployment:"
    echo "      terraform plan -var-file=environments/${ENVIRONMENT}/terraform.tfvars"
    echo ""
    echo "   3. Apply the DR deployment:"
    echo "      terraform apply -var-file=environments/${ENVIRONMENT}/terraform.tfvars"
    echo ""
    echo "   Or use the DR deployment script:"
    echo "      ./scripts/deploy-dr.sh ${ENVIRONMENT} plan"
    echo "      ./scripts/deploy-dr.sh ${ENVIRONMENT} apply"
    echo ""
    print_warning "⚠️  Important Notes:"
    echo "   • This is a separate workspace from the primary infrastructure"
    echo "   • DR infrastructure is deployed in region: $DR_REGION"
    echo "   • State is stored separately in: $BUCKET_NAME"
    echo "   • Keep backend.conf secure and do not commit to git"
    echo ""
}

# Main execution
main() {
    create_s3_bucket
    create_dynamodb_table
    generate_backend_config
    print_next_steps
}

# Run main function
main
