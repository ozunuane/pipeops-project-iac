#!/bin/bash
# Destroy all AWS resources by tags for pipeops project
# This script finds and destroys resources tagged with Project=pipeops

set -e

PROJECT_TAG="pipeops"
PROD_REGION="us-west-2"
DR_REGION="us-east-1"

echo "=========================================="
echo "Destroying all resources tagged Project=$PROJECT_TAG"
echo "=========================================="

destroy_region() {
    local region=$1
    local env=$2
    echo ""
    echo "=== Processing $env environment in $region ==="
    
    # 1. Delete EKS Clusters
    echo "Finding EKS clusters..."
    clusters=$(aws eks list-clusters --region $region --output text --query 'clusters[]' 2>/dev/null | grep -i pipeops || echo "")
    if [ ! -z "$clusters" ]; then
        for cluster in $clusters; do
            echo "  Deleting EKS cluster: $cluster"
            aws eks delete-cluster --name "$cluster" --region $region 2>&1 | grep -E "cluster|status|Error" || true
            echo "    Cluster deletion initiated (this takes 10-15 minutes)"
        done
    else
        echo "  No EKS clusters found"
    fi
    
    # 2. Delete RDS Instances
    echo "Finding RDS instances..."
    rds_instances=$(aws rds describe-db-instances --region $region --query 'DBInstances[?contains(DBInstanceIdentifier, `pipeops`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
    if [ ! -z "$rds_instances" ]; then
        for instance in $rds_instances; do
            echo "  Checking deletion protection for: $instance"
            # Disable deletion protection first
            aws rds modify-db-instance \
                --db-instance-identifier "$instance" \
                --no-deletion-protection \
                --apply-immediately \
                --region $region 2>&1 | grep -E "DBInstance|Error" || true
            echo "  Waiting 10 seconds for deletion protection to be disabled..."
            sleep 10
            echo "  Deleting RDS instance: $instance"
            aws rds delete-db-instance \
                --db-instance-identifier "$instance" \
                --skip-final-snapshot \
                --region $region 2>&1 | grep -E "DBInstance|status|Error" || true
            echo "    RDS deletion initiated"
        done
    else
        echo "  No RDS instances found"
    fi
    
    # 3. Delete Load Balancers
    echo "Finding Load Balancers..."
    elb_arns=$(aws elbv2 describe-load-balancers --region $region --query 'LoadBalancers[?contains(LoadBalancerName, `pipeops`)].LoadBalancerArn' --output text 2>/dev/null || echo "")
    if [ ! -z "$elb_arns" ]; then
        for arn in $elb_arns; do
            echo "  Deleting Load Balancer: $arn"
            aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region $region 2>&1 || true
        done
    else
        echo "  No Load Balancers found"
    fi
    
    # 4. Delete NAT Gateways
    echo "Finding NAT Gateways..."
    nat_gws=$(aws ec2 describe-nat-gateways --region $region --filter "Name=tag:Project,Values=$PROJECT_TAG" --query 'NatGateways[?State==`available`].NatGatewayId' --output text 2>/dev/null || echo "")
    if [ ! -z "$nat_gws" ]; then
        for nat in $nat_gws; do
            echo "  Deleting NAT Gateway: $nat"
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat" --region $region 2>&1 || true
        done
    else
        echo "  No NAT Gateways found"
    fi
    
    # 5. Delete VPC Endpoints
    echo "Finding VPC Endpoints..."
    vpc_endpoints=$(aws ec2 describe-vpc-endpoints --region $region --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'VpcEndpoints[?State==`available`].VpcEndpointId' --output text 2>/dev/null || echo "")
    if [ ! -z "$vpc_endpoints" ]; then
        for endpoint in $vpc_endpoints; do
            echo "  Deleting VPC Endpoint: $endpoint"
            aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$endpoint" --region $region 2>&1 || true
        done
    else
        echo "  No VPC Endpoints found"
    fi
    
    # 6. Delete Security Groups (except default)
    echo "Finding Security Groups..."
    sg_ids=$(aws ec2 describe-security-groups --region $region --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
    if [ ! -z "$sg_ids" ]; then
        for sg in $sg_ids; do
            echo "  Attempting to delete Security Group: $sg"
            aws ec2 delete-security-group --group-id "$sg" --region $region 2>&1 || echo "    (May have dependencies, will retry later)"
        done
    else
        echo "  No Security Groups found"
    fi
    
    # 7. Delete Subnets
    echo "Finding Subnets..."
    subnet_ids=$(aws ec2 describe-subnets --region $region --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    if [ ! -z "$subnet_ids" ]; then
        for subnet in $subnet_ids; do
            echo "  Deleting Subnet: $subnet"
            aws ec2 delete-subnet --subnet-id "$subnet" --region $region 2>&1 || true
        done
    else
        echo "  No Subnets found"
    fi
    
    # 8. Delete Route Tables (except main)
    echo "Finding Route Tables..."
    rt_ids=$(aws ec2 describe-route-tables --region $region --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")
    if [ ! -z "$rt_ids" ]; then
        for rt in $rt_ids; do
            echo "  Deleting Route Table: $rt"
            aws ec2 delete-route-table --route-table-id "$rt" --region $region 2>&1 || true
        done
    else
        echo "  No Route Tables found"
    fi
    
    # 9. Delete Internet Gateways
    echo "Finding Internet Gateways..."
    igw_ids=$(aws ec2 describe-internet-gateways --region $region --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
    if [ ! -z "$igw_ids" ]; then
        for igw in $igw_ids; do
            echo "  Detaching and deleting Internet Gateway: $igw"
            vpc_id=$(aws ec2 describe-internet-gateways --region $region --internet-gateway-ids "$igw" --query 'InternetGateways[0].Attachments[0].VpcId' --output text 2>/dev/null || echo "")
            if [ ! -z "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
                aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc_id" --region $region 2>&1 || true
            fi
            aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region $region 2>&1 || true
        done
    else
        echo "  No Internet Gateways found"
    fi
    
    # 10. Delete VPCs
    echo "Finding VPCs..."
    vpc_ids=$(aws ec2 describe-vpcs --region $region --filters "Name=tag:Project,Values=$PROJECT_TAG" --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
    if [ ! -z "$vpc_ids" ]; then
        for vpc in $vpc_ids; do
            echo "  Deleting VPC: $vpc"
            aws ec2 delete-vpc --vpc-id "$vpc" --region $region 2>&1 || echo "    (May have dependencies)"
        done
    else
        echo "  No VPCs found"
    fi
    
    # 11. Delete IAM Roles
    echo "Finding IAM Roles..."
    role_names=$(aws iam list-roles --query "Roles[?contains(RoleName, \`pipeops\`)].RoleName" --output text 2>/dev/null || echo "")
    if [ ! -z "$role_names" ]; then
        for role in $role_names; do
            echo "  Detaching policies and deleting IAM Role: $role"
            # Detach policies
            policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            for policy in $policies; do
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>&1 || true
            done
            # Delete inline policies
            inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            for policy in $inline_policies; do
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>&1 || true
            done
            # Delete role
            aws iam delete-role --role-name "$role" 2>&1 || echo "    (May have dependencies)"
        done
    else
        echo "  No IAM Roles found"
    fi
    
    # 12. Delete KMS Keys
    echo "Finding KMS Keys..."
    key_ids=$(aws kms list-keys --region $region --query 'Keys[].KeyId' --output text 2>/dev/null || echo "")
    if [ ! -z "$key_ids" ]; then
        for key_id in $key_ids; do
            key_tags=$(aws kms list-resource-tags --key-id "$key_id" --region $region --query 'Tags[?Key==`Project`].Value' --output text 2>/dev/null || echo "")
            if [ "$key_tags" == "$PROJECT_TAG" ]; then
                echo "  Scheduling deletion of KMS Key: $key_id"
                aws kms schedule-key-deletion --key-id "$key_id" --pending-window-in-days 7 --region $region 2>&1 || true
            fi
        done
    else
        echo "  No KMS Keys found"
    fi
    
    # 13. Delete CloudWatch Log Groups
    echo "Finding CloudWatch Log Groups..."
    log_groups=$(aws logs describe-log-groups --region $region --log-group-name-prefix "/aws/eks/pipeops" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
    if [ ! -z "$log_groups" ]; then
        for log_group in $log_groups; do
            echo "  Deleting Log Group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" --region $region 2>&1 || true
        done
    else
        echo "  No CloudWatch Log Groups found"
    fi
    
    # 14. Delete S3 Buckets (for backups, etc.)
    echo "Finding S3 Buckets..."
    buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, \`pipeops\`)].Name" --output text 2>/dev/null || echo "")
    if [ ! -z "$buckets" ]; then
        for bucket in $buckets; do
            echo "  Emptying and deleting S3 Bucket: $bucket"
            aws s3 rm "s3://$bucket" --recursive 2>&1 || true
            aws s3api delete-bucket --bucket "$bucket" 2>&1 || true
        done
    else
        echo "  No S3 Buckets found"
    fi
    
    echo ""
    echo "=== Completed $env environment in $region ==="
}

# Destroy Prod environment
destroy_region "$PROD_REGION" "PROD"

# Destroy DR environment  
destroy_region "$DR_REGION" "DR"

echo ""
echo "=========================================="
echo "Destruction initiated for all resources"
echo "=========================================="
echo ""
echo "NOTE: Some resources take time to delete:"
echo "  - EKS clusters: 10-15 minutes"
echo "  - RDS instances: 5-10 minutes"
echo "  - NAT Gateways: 2-5 minutes"
echo ""
echo "Check status with:"
echo "  aws eks describe-cluster --name <cluster-name> --region <region>"
echo "  aws rds describe-db-instances --region <region>"
