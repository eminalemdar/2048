# Kubernetes Deployment

Kubernetes manifests for deploying the 2048 game to a cluster.

## 🚀 Quick Deploy

```bash
./deploy.sh
```

## 📁 Files

- `namespace.yaml` - Creates game-2048 namespace
- `*-deployment.yaml` - Application deployments
- `*-service.yaml` - Kubernetes services
- `ingress.yaml` - External access configuration
- `hpa.yaml` - Auto-scaling configuration
- `configmap.yaml` - Application configuration

## 🌐 Access

### Port Forward
```bash
kubectl port-forward -n game-2048 svc/frontend-service 3000:80
```

### Ingress
Add to `/etc/hosts`:
```
<INGRESS_IP> 2048.local
```
Visit: http://2048.local

## 🧹 Cleanup

```bash
kubectl delete namespace game-2048
```