# Archived Kubernetes Manifests

This directory contains the **old flat structure** manifests that have been replaced by the new Kustomize-based multi-environment setup.

## ⚠️ These files are deprecated

**Do not use these files directly.** They have been replaced by the new structure in:
- `base/` - Common configurations
- `overlays/` - Environment-specific patches

## 📁 Archived Files

- `app-of-apps.yaml` - Replaced by `base/argocd/app-of-apps.yaml` + environment patches
- `sample-app.yaml` - Example application (moved to `base/argocd/`)
- `ingress-class.yaml` - Replaced by `base/ingress-controller/ingress-class.yaml`
- `service-monitor.yaml` - Replaced by `base/monitoring/service-monitors.yaml`

## 🔄 Migration Path

If you were using these files before:

### Old Way (Deprecated)
```bash
kubectl apply -f argocd/app-of-apps.yaml
kubectl apply -f ingress-controller/ingress-class.yaml
```

### New Way (Recommended)
```bash
# For development
kubectl apply -k overlays/dev

# For staging
kubectl apply -k overlays/staging

# For production
kubectl apply -k overlays/prod
```

## 📚 Documentation

See the main [k8s-manifests/README.md](../README.md) for complete documentation on the new structure.

---

**Archived Date**: 2026-01-21  
**Reason**: Replaced with Kustomize multi-environment setup
