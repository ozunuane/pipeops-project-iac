#!/bin/bash
set -e

# Prerequisites Setup Script
# This script helps set up the required AWS resources for the Terraform backend

ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

create_s3_backend_bucket() {
    BUCKET_NAME="pipeops-terraform-state-${ENVIRONMENT}-${ACCOUNT_ID}"

    log_info "Creating S3 bucket for Terraform state: $BUCKET_NAME"

    # Create bucket
    if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || {
                if [[ "$REGION" == "us-east-1" ]]; then
                    aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"
                else
                    aws s3api create-bucket \
                        --bucket "$BUCKET_NAME" \
                        --region "$REGION" \
                        --create-bucket-configuration LocationConstraint="$REGION"
                fi
            }

        log_success "S3 bucket created: $BUCKET_NAME"
    else
        log_info "S3 bucket already exists: $BUCKET_NAME"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'

    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

    log_success "S3 bucket configured with versioning, encryption, and public access blocked"

    echo "S3_BUCKET=$BUCKET_NAME" >> ".env.$ENVIRONMENT"
}

create_dynamodb_lock_table() {
    TABLE_NAME="terraform-state-lock-${ENVIRONMENT}"

    log_info "Creating DynamoDB table for state locking: $TABLE_NAME"

    # Check if table exists
    if ! aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
        aws dynamodb create-table \
            --table-name "$TABLE_NAME" \
            --attribute-definitions AttributeName=LockID,AttributeType=S \
            --key-schema AttributeName=LockID,KeyType=HASH \
            --billing-mode PAY_PER_REQUEST \
            --region "$REGION"

        log_info "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"

        log_success "DynamoDB table created: $TABLE_NAME"
    else
        log_info "DynamoDB table already exists: $TABLE_NAME"
    fi

    echo "DYNAMODB_TABLE=$TABLE_NAME" >> ".env.$ENVIRONMENT"
}

create_kms_key() {
    log_info "Creating KMS key for encryption..."

    KEY_ALIAS="alias/pipeops-${ENVIRONMENT}-terraform"

    # Check if key alias exists
    if ! aws kms describe-key --key-id "$KEY_ALIAS" --region "$REGION" >/dev/null 2>&1; then
        KEY_ID=$(aws kms create-key \
            --region "$REGION" \
            --description "KMS key for pipeops $ENVIRONMENT environment" \
            --query 'KeyMetadata.KeyId' \
            --output text)

        aws kms create-alias \
            --alias-name "$KEY_ALIAS" \
            --target-key-id "$KEY_ID" \
            --region "$REGION"

        log_success "KMS key created with alias: $KEY_ALIAS"
        echo "KMS_KEY_ID=$KEY_ID" >> ".env.$ENVIRONMENT"
    else
        log_info "KMS key alias already exists: $KEY_ALIAS"
        KEY_ID=$(aws kms describe-key --key-id "$KEY_ALIAS" --region "$REGION" --query 'KeyMetadata.KeyId' --output text)
        echo "KMS_KEY_ID=$KEY_ID" >> ".env.$ENVIRONMENT"
    fi
}

create_iam_roles() {
    log_info "Creating basic IAM roles for the deployment..."

    # Create a role for the deployment user (optional - for CI/CD)
    ROLE_NAME="pipeops-${ENVIRONMENT}-deploy-role"

    TRUST_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'$ACCOUNT_ID':root"
                },
                "Action": "sts:AssumeRole",
                "Condition": {
                    "StringEquals": {
                        "sts:ExternalId": "pipeops-'$ENVIRONMENT'-deploy"
                    }
                }
            }
        ]
    }'

    # Create role if it doesn't exist
    if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY"

        # Attach necessary policies (be more restrictive in production)
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

        log_success "IAM role created: $ROLE_NAME"
    else
        log_info "IAM role already exists: $ROLE_NAME"
    fi

    echo "DEPLOY_ROLE_ARN=arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}" >> ".env.$ENVIRONMENT"
}

generate_backend_config() {
    BUCKET_NAME="pipeops-terraform-state-${ENVIRONMENT}-${ACCOUNT_ID}"
    TABLE_NAME="terraform-state-lock-${ENVIRONMENT}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    BACKEND_CONF_DIR="$ROOT_DIR/environments/$ENVIRONMENT"

    log_info "Generating backend configuration..."

    # Create environments directory if it doesn't exist
    mkdir -p "$BACKEND_CONF_DIR"

    # Generate backend.conf in the environment directory
    cat > "$BACKEND_CONF_DIR/backend.conf" << EOF
key      = "pipeops-project-iac-${ENVIRONMENT}-terraform.tfstate"
region   = "${REGION}"
encrypt  = true
dynamodb_table = "${TABLE_NAME}"
bucket   = "${BUCKET_NAME}"
EOF

    log_success "Backend configuration written to environments/$ENVIRONMENT/backend.conf"
    
    # Also generate a human-readable reference file at root
    cat > "$ROOT_DIR/backend-${ENVIRONMENT}.hcl" << EOF
# Backend configuration for $ENVIRONMENT environment
# This is a reference file. The actual config is in: environments/$ENVIRONMENT/backend.conf
# Usage: terraform init -backend-config=environments/$ENVIRONMENT/backend.conf

bucket         = "${BUCKET_NAME}"
key            = "pipeops-project-iac-${ENVIRONMENT}-terraform.tfstate"
region         = "${REGION}"
encrypt        = true
dynamodb_table = "${TABLE_NAME}"
EOF

    log_info "Reference configuration also written to backend-${ENVIRONMENT}.hcl"
}

setup_environment_file() {
    log_info "Setting up environment file..."

    cat > ".env.$ENVIRONMENT" << EOF
# Environment variables for $ENVIRONMENT
AWS_REGION=$REGION
ENVIRONMENT=$ENVIRONMENT
ACCOUNT_ID=$ACCOUNT_ID
EOF

    log_success "Environment file created: .env.$ENVIRONMENT"
}

validate_setup() {
    log_info "Validating setup..."

    BUCKET_NAME="pipeops-terraform-state-${ENVIRONMENT}-${ACCOUNT_ID}"
    TABLE_NAME="terraform-state-lock-${ENVIRONMENT}"

    # Test S3 bucket
    if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
        log_success "✓ S3 bucket accessible"
    else
        log_error "✗ S3 bucket not accessible"
        exit 1
    fi

    # Test DynamoDB table
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
        log_success "✓ DynamoDB table accessible"
    else
        log_error "✗ DynamoDB table not accessible"
        exit 1
    fi

    log_success "All prerequisites validated successfully!"
}

print_next_steps() {
    BUCKET_NAME="pipeops-terraform-state-${ENVIRONMENT}-${ACCOUNT_ID}"
    TABLE_NAME="terraform-state-lock-${ENVIRONMENT}"

    log_success "Prerequisites setup completed!"
    echo ""
    log_info "=== RESOURCES CREATED ==="
    log_info "✓ S3 Bucket:       $BUCKET_NAME"
    log_info "✓ DynamoDB Table:  $TABLE_NAME"
    log_info "✓ KMS Key:         alias/pipeops-${ENVIRONMENT}-terraform"
    log_info "✓ Backend Config:  environments/$ENVIRONMENT/backend.conf"
    echo ""
    log_info "=== NEXT STEPS ==="
    log_info "1. Review the backend configuration:"
    log_info "   cat environments/$ENVIRONMENT/backend.conf"
    echo ""
    log_info "2. Plan your deployment (this will automatically initialize the backend):"
    log_info "   ./scripts/deploy.sh $ENVIRONMENT plan"
    echo ""
    log_info "3. Apply your deployment:"
    log_info "   ./scripts/deploy.sh $ENVIRONMENT apply"
    echo ""
    log_info "The deploy.sh script will automatically use the backend.conf file!"
}

main() {
    log_info "Setting up prerequisites for $ENVIRONMENT environment in region $REGION"
    log_info "Account ID: $ACCOUNT_ID"

    setup_environment_file
    create_s3_backend_bucket
    create_dynamodb_lock_table
    create_kms_key
    create_iam_roles
    generate_backend_config
    validate_setup
    print_next_steps
}

# Run main function
main