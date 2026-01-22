#!/bin/bash
set -e

# Prerequisites Setup Script
# This script helps set up the required AWS resources for the Terraform backend
# and configures GitHub Actions OIDC authentication
#
# Usage:
#   ./scripts/setup-prerequisites.sh [ENVIRONMENT] [REGION]
#
# Examples:
#   ./scripts/setup-prerequisites.sh dev us-east-1
#   ./scripts/setup-prerequisites.sh prod us-west-2
#   PROJECT_NAME=myproject ./scripts/setup-prerequisites.sh dev
#   SKIP_OIDC=true ./scripts/setup-prerequisites.sh dev
#
# Environment Variables:
#   PROJECT_NAME - Project name (default: pipeops)
#   SKIP_OIDC    - Skip OIDC setup (default: false)
#
# What this script creates:
#   ✓ S3 bucket for Terraform state
#   ✓ DynamoDB table for state locking
#   ✓ KMS key for encryption
#   ✓ GitHub OIDC provider (once per AWS account)
#   ✓ IAM role for GitHub Actions (per environment)
#   ✓ Backend configuration file

# Configuration
PROJECT_NAME=${PROJECT_NAME:-pipeops}  # Can be overridden via environment variable
ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}
SKIP_OIDC=${SKIP_OIDC:-false}  # Set to 'true' to skip OIDC setup
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
    BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-state"

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
    TABLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-locks"

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

    KEY_ALIAS="alias/${PROJECT_NAME}-${ENVIRONMENT}-terraform"

    # Check if key alias exists
    if ! aws kms describe-key --key-id "$KEY_ALIAS" --region "$REGION" >/dev/null 2>&1; then
        KEY_ID=$(aws kms create-key \
            --region "$REGION" \
            --description "KMS key for ${PROJECT_NAME} ${ENVIRONMENT} environment" \
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

create_github_oidc_provider() {
    log_info "Setting up GitHub OIDC provider (if not exists)..."
    
    OIDC_PROVIDER_URL="token.actions.githubusercontent.com"
    OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER_URL}"
    
    # Check if OIDC provider already exists
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
        log_info "GitHub OIDC provider already exists"
    else
        log_info "Creating GitHub OIDC provider..."
        aws iam create-open-id-connect-provider \
            --url "https://${OIDC_PROVIDER_URL}" \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
            --tags Key=ManagedBy,Value=setup-prerequisites Key=Project,Value=${PROJECT_NAME}
        
        log_success "GitHub OIDC provider created"
    fi
    
    echo "OIDC_PROVIDER_ARN=${OIDC_PROVIDER_ARN}" >> ".env.$ENVIRONMENT"
}

create_github_actions_oidc_role() {
    log_info "Creating GitHub Actions OIDC role for ${ENVIRONMENT}..."
    
    ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-github-actions"
    
    # Check if GitHub org/repo are provided as environment variables
    if [[ -z "$GITHUB_ORG" ]] && [[ -z "$GITHUB_REPO" ]]; then
        # Try to load from saved config file
        GITHUB_CONFIG_FILE=".github-config"
        if [[ -f "$GITHUB_CONFIG_FILE" ]]; then
            source "$GITHUB_CONFIG_FILE"
            log_info "Using saved GitHub configuration: ${GITHUB_ORG}/${GITHUB_REPO}"
        else
            # Prompt only if not provided and no saved config
            if [ -t 0 ]; then
                log_info "GitHub repository information (will be saved for reuse)"
                read -p "Enter GitHub organization/username (default: your-org): " GITHUB_ORG
                read -p "Enter GitHub repository name (default: ${PROJECT_NAME}-project-iac): " GITHUB_REPO
                
                GITHUB_ORG=${GITHUB_ORG:-your-org}
                GITHUB_REPO=${GITHUB_REPO:-${PROJECT_NAME}-project-iac}
                
                # Save for next time
                cat > "$GITHUB_CONFIG_FILE" << EOF
# GitHub configuration for OIDC setup
# Auto-generated by setup-prerequisites.sh
GITHUB_ORG="${GITHUB_ORG}"
GITHUB_REPO="${GITHUB_REPO}"
EOF
                log_success "GitHub configuration saved to $GITHUB_CONFIG_FILE"
            else
                # Non-interactive mode
                GITHUB_ORG=${GITHUB_ORG:-your-org}
                GITHUB_REPO=${GITHUB_REPO:-${PROJECT_NAME}-project-iac}
            fi
        fi
    else
        log_info "Using GitHub configuration from environment: ${GITHUB_ORG}/${GITHUB_REPO}"
    fi
    
    # Determine which branch patterns can assume this role based on environment
    # Using StringLike to support both direct branch pushes and pull request events
    if [[ "$ENVIRONMENT" == "dev" ]]; then
        ALLOWED_BRANCH_PATTERN="repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        # Dev can be triggered from any branch (PRs, develop, feature branches)
    else
        ALLOWED_BRANCH_PATTERN="repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        # Prod/staging typically from main, but allow flexibility for workflow_dispatch
    fi
    
    # Create trust policy for GitHub OIDC
    # Using StringLike with wildcard to support various GitHub Actions contexts:
    # - Direct branch push: repo:ORG/REPO:ref:refs/heads/BRANCH
    # - Pull request: repo:ORG/REPO:pull_request
    # - Workflow dispatch: repo:ORG/REPO:ref:refs/heads/BRANCH
    # - Environment: repo:ORG/REPO:environment:ENV_NAME
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "${ALLOWED_BRANCH_PATTERN}"
        }
      }
    }
  ]
}
EOF
)
    
    # Create role if it doesn't exist, or update trust policy if it does
    if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" \
            --description "GitHub Actions OIDC role for ${PROJECT_NAME} ${ENVIRONMENT} environment" \
            --max-session-duration 3600 \
            --tags Key=ManagedBy,Value=setup-prerequisites Key=Project,Value=${PROJECT_NAME} Key=Environment,Value=${ENVIRONMENT}
        
        # Attach necessary policies (be more restrictive in production)
        log_info "Attaching IAM policies to role..."
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
        
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
        
        log_success "GitHub Actions OIDC role created: $ROLE_NAME"
        log_info "Allowed repository: ${GITHUB_ORG}/${GITHUB_REPO}"
        log_info "Allowed contexts: All branches, PRs, and workflow dispatches"
    else
        log_info "GitHub Actions OIDC role already exists: $ROLE_NAME"
        log_info "Updating trust policy to ensure correct GitHub repository access..."
        aws iam update-assume-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-document "$TRUST_POLICY"
        log_success "Trust policy updated for: $ROLE_NAME"
        log_info "Allowed repository: ${GITHUB_ORG}/${GITHUB_REPO}"
        log_info "Allowed contexts: All branches, PRs, and workflow dispatches"
    fi
    
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    echo "GITHUB_ACTIONS_ROLE_ARN=${ROLE_ARN}" >> ".env.$ENVIRONMENT"
    
    log_warning "⚠️  Add this to your GitHub repository secrets:"
    log_warning "   Secret name: AWS_ROLE_ARN_$(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')"
    log_warning "   Secret value: ${ROLE_ARN}"
}

create_iam_roles() {
    if [[ "$SKIP_OIDC" == "true" ]]; then
        log_warning "Skipping OIDC setup (SKIP_OIDC=true)"
        log_info "You will need to configure AWS authentication manually"
        echo "OIDC_SETUP=skipped" >> ".env.$ENVIRONMENT"
        return
    fi
    
    log_info "Setting up IAM roles for deployment..."
    
    # Create GitHub OIDC provider (once per account)
    create_github_oidc_provider
    
    # Create GitHub Actions OIDC role (per environment)
    create_github_actions_oidc_role
}

generate_backend_config() {
    BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-state"
    TABLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-locks"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    BACKEND_CONF_DIR="$ROOT_DIR/environments/$ENVIRONMENT"

    log_info "Generating backend configuration..."

    # Create environments directory if it doesn't exist
    mkdir -p "$BACKEND_CONF_DIR"

    # Generate backend.conf in the environment directory
    cat > "$BACKEND_CONF_DIR/backend.conf" << EOF
key      = "${ENVIRONMENT}/terraform.tfstate"
region   = "${REGION}"
encrypt  = true
dynamodb_table = "${TABLE_NAME}"
bucket   = "${BUCKET_NAME}"
EOF

    log_success "Backend configuration written to environments/$ENVIRONMENT/backend.conf"
    
    # Also generate a human-readable reference file at root
    cat > "$ROOT_DIR/backend-${ENVIRONMENT}.hcl" << EOF
# Backend configuration for $ENVIRONMENT environment
# Project: ${PROJECT_NAME}
# This is a reference file. The actual config is in: environments/$ENVIRONMENT/backend.conf
# Usage: terraform init -backend-config=environments/$ENVIRONMENT/backend.conf

bucket         = "${BUCKET_NAME}"
key            = "${ENVIRONMENT}/terraform.tfstate"
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

    BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-state"
    TABLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-locks"

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
    BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-state"
    TABLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-terraform-locks"

    log_success "Prerequisites setup completed!"
    echo ""
    log_info "=== RESOURCES CREATED ==="
    log_info "✓ Project:         $PROJECT_NAME"
    log_info "✓ Environment:     $ENVIRONMENT"
    log_info "✓ S3 Bucket:       $BUCKET_NAME"
    log_info "✓ DynamoDB Table:  $TABLE_NAME"
    log_info "✓ KMS Key:         alias/${PROJECT_NAME}-${ENVIRONMENT}-terraform"
    
    if [[ "$SKIP_OIDC" != "true" ]]; then
        ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-github-actions"
        ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
        
        log_info "✓ OIDC Provider:   token.actions.githubusercontent.com"
        log_info "✓ IAM Role:        $ROLE_NAME"
    fi
    
    log_info "✓ Backend Config:  environments/$ENVIRONMENT/backend.conf"
    echo ""
    
    if [[ "$SKIP_OIDC" != "true" ]]; then
        ROLE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-github-actions"
        ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
        
        log_warning "=== GITHUB ACTIONS SETUP REQUIRED ==="
        log_warning "Add this secret to your GitHub repository:"
        echo ""
        log_warning "  Secret Name:  AWS_ROLE_ARN_$(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')"
        log_warning "  Secret Value: ${ROLE_ARN}"
        echo ""
        log_info "To add via GitHub CLI:"
        log_info "  gh secret set AWS_ROLE_ARN_$(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]') \\"
        log_info "    --body \"${ROLE_ARN}\" \\"
        log_info "    --repo YOUR_ORG/YOUR_REPO"
        echo ""
        log_info "Or via GitHub Web UI:"
        log_info "  1. Go to: Settings → Secrets and variables → Actions"
        log_info "  2. Click: New repository secret"
        log_info "  3. Name: AWS_ROLE_ARN_$(echo $ENVIRONMENT | tr '[:lower:]' '[:upper:]')"
        log_info "  4. Value: ${ROLE_ARN}"
        echo ""
    fi
    
    log_info "=== NEXT STEPS ==="
    
    if [[ "$SKIP_OIDC" != "true" ]]; then
        log_info "1. Add the GitHub secret (see above)"
        echo ""
        log_info "2. Review the backend configuration:"
    else
        log_info "1. Review the backend configuration:"
    fi
    
    log_info "   cat environments/$ENVIRONMENT/backend.conf"
    echo ""
    
    if [[ "$SKIP_OIDC" != "true" ]]; then
        log_info "3. (Optional) Test local deployment:"
    else
        log_info "2. (Optional) Test local deployment:"
    fi
    
    log_info "   ./scripts/deploy.sh $ENVIRONMENT plan"
    log_info "   ./scripts/deploy.sh $ENVIRONMENT apply"
    echo ""
    
    if [[ "$SKIP_OIDC" != "true" ]]; then
        log_info "4. Push to GitHub and let CI/CD handle deployments!"
        echo ""
        log_info "The GitHub Actions workflows will automatically use OIDC authentication!"
    else
        log_warning "⚠️  OIDC was skipped. Configure AWS authentication for GitHub Actions:"
        log_info "   - See: .github/workflows/AWS_OIDC_SETUP_GUIDE.md"
        log_info "   - Or use AWS access keys (not recommended for production)"
    fi
}

main() {
    log_info "=== Prerequisites Setup ==="
    log_info "Project:       $PROJECT_NAME"
    log_info "Environment:   $ENVIRONMENT"
    log_info "Region:        $REGION"
    log_info "Account ID:    $ACCOUNT_ID"
    echo ""

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
main