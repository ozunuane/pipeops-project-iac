# Quick Start Guide

**Get your environment running in 5 minutes!**

## 🚀 Choose Your Environment

<details>
<summary><strong>Development (Local Testing)</strong></summary>

### Cost: ~$100/month | Region: us-east-1 | Setup Time: 15 minutes

```bash
# 1. Setup AWS resources
./scripts/setup-prerequisites.sh dev us-east-1

# 2. Deploy infrastructure
./scripts/deploy.sh dev apply

# 3. Access services
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080

# Get password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

**What you get:**
- ✅ Single-AZ RDS (db.t3.micro)
- ✅ EKS cluster with Auto Mode
- ✅ ArgoCD for GitOps
- ✅ Monitoring stack (Prometheus/Grafana)
- ✅ Internal-only access (no public ingress)

</details>

<details>
<summary><strong>Staging (Pre-Production)</strong></summary>

### Cost: ~$300/month | Region: us-west-2 | Setup Time: 25 minutes

```bash
# 1. Setup AWS resources
./scripts/setup-prerequisites.sh staging us-west-2

# 2. Configure SSL certificate
aws acm request-certificate \
  --region us-west-2 \
  --domain-name "app-staging.yourdomain.com" \
  --validation-method DNS

# 3. Update domain in config
vim k8s-manifests/overlays/staging/ingress-patch.yaml
# Change: host: app-staging.yourdomain.com

# 4. Deploy infrastructure
./scripts/deploy.sh staging apply

# 5. Configure DNS
# Create CNAME: app-staging.yourdomain.com → <ALB-DNS>
```

**What you get:**
- ✅ Multi-AZ RDS (db.r6g.large)
- ✅ EKS cluster with Auto Mode
- ✅ Public ingress with SSL
- ✅ ArgoCD + Monitoring
- ✅ Production-like environment

</details>

<details>
<summary><strong>Production (Live)</strong></summary>

### Cost: ~$1000/month | Region: us-west-2 + us-east-1 (DR) | Setup Time: 30 minutes

**⚠️ Complete the [Production Checklist](#production-checklist) first!**

```bash
# 1. Setup AWS resources
./scripts/setup-prerequisites.sh prod us-west-2

# 2. Configure SSL + WAF
aws acm request-certificate --region us-west-2 \
  --domain-name "app.yourdomain.com" \
  --validation-method DNS

# 3. Configure PagerDuty
aws secretsmanager create-secret \
  --name pipeops/prod/pagerduty \
  --secret-string '{"integration_key":"YOUR_KEY"}'

# 4. Review configuration
cat environments/prod/terraform.tfvars
# Verify: db_multi_az = true, db_enable_cross_region_dr = true

# 5. Plan deployment (REVIEW CAREFULLY!)
./scripts/deploy.sh prod plan | tee prod-plan.txt

# 6. Deploy infrastructure
./scripts/deploy.sh prod apply

# 7. Configure DNS and verify
# Create A/CNAME: app.yourdomain.com → <ALB-DNS>
curl -I https://app.yourdomain.com/health
```

**What you get:**
- ✅ Multi-AZ RDS + DR replica in us-east-1
- ✅ EKS cluster with Auto Mode
- ✅ Public ingress with SSL + WAF
- ✅ ArgoCD + Enhanced Monitoring
- ✅ PagerDuty alerts
- ✅ Resource quotas and limits

</details>

## 📋 Production Checklist

Before deploying to production:

- [ ] Security audit completed
- [ ] SSL certificates provisioned (ACM)
- [ ] WAF rules configured
- [ ] PagerDuty integration tested
- [ ] Backup retention configured (30 days)
- [ ] DR failover plan documented
- [ ] Cost budget alerts set up
- [ ] Change management approval obtained
- [ ] Rollback procedure tested
- [ ] Team trained on operations

## 🔧 Essential Commands

### Check Status
```bash
# EKS cluster
kubectl get nodes

# All pods
kubectl get pods -A

# RDS status
aws rds describe-db-instances \
  --db-instance-identifier pipeops-<env>-postgres

# ArgoCD apps
kubectl get applications -n argocd
```

### Access Services
```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090
```

### Deploy Applications
```bash
# Via kubectl
kubectl apply -k k8s-manifests/overlays/<env>

# Via ArgoCD
kubectl apply -f k8s-manifests/argocd/applicationset.yaml
```

## 🆘 Quick Troubleshooting

### "Backend not found"
```bash
# Run prerequisites first
./scripts/setup-prerequisites.sh <env> <region>
```

### "State locked"
```bash
# Force unlock (if safe)
terraform force-unlock <LOCK_ID>
```

### "Can't access EKS"
```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region <region> \
  --name pipeops-<env>-eks
```

### "RDS connection refused"
```bash
# Check security groups
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <RDS_ENDPOINT> -U postgres
```

## 📚 Full Documentation

- **[Environment Deployment Guide](ENVIRONMENT_DEPLOYMENT_GUIDE.md)** - Complete deployment instructions
- **[Deployment Workflow](DEPLOYMENT_WORKFLOW.md)** - Detailed workflow and architecture
- **[RDS Complete Guide](RDS_COMPLETE_GUIDE.md)** - Database HA and DR setup
- **[K8s Manifests README](k8s-manifests/README.md)** - Kubernetes configuration guide

## 🎯 Next Steps

After deployment:

1. **Configure monitoring alerts**
   ```bash
   # View Prometheus alerts
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   ```

2. **Deploy your applications**
   ```bash
   kubectl apply -k k8s-manifests/overlays/<env>
   ```

3. **Set up CI/CD pipeline**
   - Configure GitHub Actions / GitLab CI
   - Use deploy.sh in pipeline
   - Implement automated testing

4. **Test disaster recovery**
   ```bash
   # Promote DR RDS (in maintenance window)
   aws rds promote-read-replica \
     --db-instance-identifier pipeops-prod-postgres-dr
   ```

5. **Monitor costs**
   ```bash
   aws ce get-cost-and-usage \
     --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
     --granularity MONTHLY \
     --metrics UnblendedCost
   ```

## 💡 Pro Tips

- 🔒 **Never** commit `terraform.tfvars` with real values
- 📊 Run `terraform plan` before every `apply`
- 🔄 Test changes in dev → staging → production
- 💾 Back up state files regularly (S3 versioning is enabled)
- 📈 Monitor costs weekly to avoid surprises
- 🚨 Set up CloudWatch billing alarms
- 🔐 Enable MFA for production AWS access
- 📝 Document all production changes
- 🧪 Test disaster recovery quarterly
- 🤖 Automate everything possible

## 🆘 Need Help?

- 📖 Read the [full documentation](ENVIRONMENT_DEPLOYMENT_GUIDE.md)
- 🔍 Check [troubleshooting section](ENVIRONMENT_DEPLOYMENT_GUIDE.md#troubleshooting)
- 💬 Contact platform team: platform-team@yourcompany.com

---

**Quick Start Version**: 1.0  
**Last Updated**: 2026-01-21  
**Maintained By**: Platform Team
