#!/usr/bin/env bash
# Install Gateway API CRDs (standard, experimental) and AWS LBC gateway-specific CRDs.
# Usage: ./install-gateway-api-crds.sh <cluster-name> <aws-region> [role-arn]
#   role-arn: optional; use for aws eks update-kubeconfig --role-arn (e.g. eks-exec in CI).
# Requires: aws CLI, kubectl, cluster accessible via current AWS credentials.

set -euo pipefail
CLUSTER_NAME="${1:?Usage: $0 <cluster-name> <aws-region> [role-arn]}"
AWS_REGION="${2:?Usage: $0 <cluster-name> <aws-region> [role-arn]}"
ROLE_ARN="${3:-}"

export AWS_REGION
UPDATE_KUBECONFIG=(aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION")
[[ -n "$ROLE_ARN" ]] && UPDATE_KUBECONFIG+=(--role-arn "$ROLE_ARN")
"${UPDATE_KUBECONFIG[@]}"

GATEWAY_API_VERSION="v1.3.0"
LBC_GATEWAY_CRDS="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/config/crd/gateway/gateway-crds.yaml"

echo "Applying Gateway API standard CRDs (${GATEWAY_API_VERSION})..."
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "Applying Gateway API experimental CRDs (${GATEWAY_API_VERSION})..."
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml" || true

echo "Applying AWS LBC Gateway API CRDs..."
kubectl apply -f "$LBC_GATEWAY_CRDS"

echo "Gateway API CRDs installed."
