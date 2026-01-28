#!/bin/bash
set -euxo pipefail

echo "Scaling up the inflate deployment to trigger Karpenter provisioning..."

# Scale up the deployment to trigger node provisioning
kubectl scale deployment inflate --replicas=9 -n default

echo ""
echo "Deployment scaled to 5 replicas. Monitoring cluster events..."

# Monitor for new nodes
echo "Waiting for new nodes to be created..."
while true; do
  NEW_NODES=$(kubectl get nodes -l karpenter.sh/node-group=default -o jsonpath='{range .items[?(@.metadata.creationTimestamp > "1m")]}{.metadata.name}{"\n"}{end}' | wc -l)
  if [ "$NEW_NODES" -gt 0 ]; then
    echo "New nodes detected! Scaling down to 1 replica..."
    kubectl scale deployment inflate --replicas=1 -n default
    echo "Deployment scaled down to 1 replica. Monitoring complete."
    break
  fi
  sleep 5
done