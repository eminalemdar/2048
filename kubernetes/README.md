# Kubernetes Deployment

This directory contains plain Kubernetes manifests for deploying the 2048 game.

> **⚠️ The KRO-based approach in the `kro/` directory is the recommended path.**
> It provisions the AWS resources (DynamoDB tables, S3 bucket, IAM role) as part
> of the deployment. The manifests here assume those resources already exist and
> only deploy the workloads.
>
> **Deploy one path or the other, never both against the same cluster.** The two
> use different resource names, so neither updates the other — you would end up
> with two parallel copies of the app and **two ALB Ingresses, meaning two load
> balancers to pay for**:
>
> | Resource | kro (`kro/`) | plain manifests (here) |
> |----------|--------------|------------------------|
> | Deployments | `game2048-backend`, `game2048-frontend` | `backend-deployment`, `frontend-deployment` |
> | Services | `game2048-backend-service`, `game2048-frontend-service` | `backend-service`, `frontend-service` |
> | Ingress | `game2048-ingress` | `game-2048-ingress` |
>
> `kubectl get deploy -n game-2048` tells you which one is live.

## 🏗️ Prerequisites

1. **EKS cluster with Auto Mode** deployed via OpenTofu (see `../opentofu/README.md`)
2. **kubectl configured** to connect to that cluster
3. **DynamoDB tables** created — via the KRO path, or manually (below)
4. **S3 bucket** for the leaderboard backup (optional, but the backend expects
   it when `S3_ENABLED=true`)
5. **IAM role for the backend ServiceAccount** (IRSA), with the policy below

> These manifests target **EKS Auto Mode's** built-in load balancing. They no
> longer work on a local kind/minikube cluster — the `nginx` IngressClass and
> the `2048.local` host entry are gone, replaced by an ALB.

## 🚀 Deployment

### Quick Deploy

```bash
./deploy.sh
```

### Manual Deployment

```bash
# Create namespace
kubectl apply -f namespace.yaml

# IngressClass for Auto Mode's ALB — must exist before the Ingress
kubectl apply -f auto-mode-ingressclass.yaml

# Deploy application components
kubectl apply -f backend-deployment.yaml
kubectl apply -f backend-service.yaml
kubectl apply -f frontend-deployment.yaml
kubectl apply -f frontend-service.yaml

# Configure networking
kubectl apply -f ingress.yaml

# Optional: Enable auto-scaling
kubectl apply -f hpa.yaml
```

### Container images

The deployments reference published images (`emnalmdr/2048-backend:v9`,
`emnalmdr/2048-frontend:v9`). `deploy.sh` does **not** build locally: EKS nodes
cannot pull a local `2048-backend:latest` tag. To ship your own build:

```bash
../scripts/build_and_push.sh v8      # builds + pushes multi-arch images
# then update the image tags in backend-deployment.yaml / frontend-deployment.yaml
```

## 📁 Manifest Files

| File | Purpose |
|------|---------|
| `namespace.yaml` | Creates `game-2048` namespace |
| `auto-mode-ingressclass.yaml` | `alb` IngressClass + IngressClassParams for Auto Mode |
| `backend-deployment.yaml` | Go backend deployment (2 replicas, non-root, read-only rootfs) |
| `backend-service.yaml` | Backend service (ClusterIP, port 8000) |
| `frontend-deployment.yaml` | Frontend deployment (2 replicas, non-root, serves on **8080**) |
| `frontend-service.yaml` | Frontend service (ClusterIP, port 80 → targetPort 8080) |
| `ingress.yaml` | ALB ingress for external access |
| `hpa.yaml` | Horizontal Pod Autoscalers (backend + frontend) — **needs a metrics API, see [Autoscaling](#-autoscaling)** |
| `configmap.yaml` | Application configuration (currently unused by the deployments) |

### A note on ports

The frontend runs the **unprivileged** nginx image as uid 101, which cannot bind
a port below 1024. The container listens on **8080**; the Service still exposes
**80**, so nothing upstream changes.

## 🗄️ Database Requirements

- **Leaderboard**: `game2048-leaderboard-dev`
- **Game Sessions**: `game2048-sessions-dev`

### Create Tables Manually

```bash
# Leaderboard table.
#
# The ScoreIndex GSI uses a CONSTANT partition key (`leaderboard`) with `score`
# as the sort key. This is deliberate: a DynamoDB Query requires an equality
# condition on the partition key, so an index keyed on `score` itself cannot
# answer "top N by score" and would force a full table scan.
aws dynamodb create-table \
  --table-name game2048-leaderboard-dev \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=leaderboard,AttributeType=S \
    AttributeName=score,AttributeType=N \
  --key-schema \
    AttributeName=id,KeyType=HASH \
  --global-secondary-indexes \
    'IndexName=ScoreIndex,KeySchema=[{AttributeName=leaderboard,KeyType=HASH},{AttributeName=score,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
  --billing-mode PAY_PER_REQUEST

# Game sessions table
aws dynamodb create-table \
  --table-name game2048-sessions-dev \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# Sessions expire via TTL
aws dynamodb update-time-to-live \
  --table-name game2048-sessions-dev \
  --time-to-live-specification "Enabled=true,AttributeName=ttl"
```

> ⚠️ A GSI's key schema **cannot be changed after creation** — DynamoDB rejects
> the update. A table created with an older `ScoreIndex` must have the index (or
> the table) deleted and recreated.

### S3 backup bucket (optional)

```bash
aws s3api create-bucket --bucket <your-unique-bucket-name> \
  --region eu-west-1 --create-bucket-configuration LocationConstraint=eu-west-1
```

Then set `S3_ENABLED=true` and `S3_BUCKET=<your-unique-bucket-name>` on the
backend deployment.

## 🔐 IAM Requirements

The backend pods reach AWS through **IRSA**. Create a role whose trust policy
allows the `game2048-backend` ServiceAccount in the `game-2048` namespace, and
annotate the ServiceAccount with `eks.amazonaws.com/role-arn`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/game2048-leaderboard-dev",
        "arn:aws:dynamodb:*:*:table/game2048-sessions-dev",
        "arn:aws:dynamodb:*:*:table/game2048-leaderboard-dev/index/*",
        "arn:aws:dynamodb:*:*:table/game2048-sessions-dev/index/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::<your-backup-bucket>/leaderboard/*"
    }
  ]
}
```

> `dynamodb:Scan` is no longer required — the leaderboard is read with a `Query`
> against `ScoreIndex`. The S3 statement is only needed when the backup is
> enabled; it is scoped to the `leaderboard/*` prefix rather than the bucket.

## 🌐 Access the Application

### Via ALB Ingress

```bash
kubectl get ingress game-2048-ingress -n game-2048 \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

> ⚠️ **Use an explicit `http://` prefix.** Only an HTTP (port 80) listener is
> created. Browsers try HTTPS first for a bare hostname and will report the site
> as unreachable even while the app is healthy.

### Via Port Forward

```bash
# Frontend (Service port 80 -> container 8080)
kubectl port-forward -n game-2048 svc/frontend-service 3000:80

# Backend API
kubectl port-forward -n game-2048 svc/backend-service 8000:8000
```

## 🔍 Monitoring

```bash
kubectl get pods -n game-2048

kubectl logs -f deployment/backend-deployment -n game-2048
kubectl logs -f deployment/frontend-deployment -n game-2048

kubectl describe ingress game-2048-ingress -n game-2048

# Confirm the IngressClass points at Auto Mode
kubectl get ingressclass alb -o jsonpath='{.spec.controller}'   # eks.amazonaws.com/alb
```

## 📈 Autoscaling

`hpa.yaml` defines HPAs for the backend (2–10 replicas) and frontend (2–5), both
on CPU/memory targets. Two things to know before relying on it:

**1. It belongs to this path only.** Its `scaleTargetRef` names
`backend-deployment` / `frontend-deployment`, which exist only in these plain
manifests. The kro `Game2048Application` does not include an HPA at all, so on
the kro path this file does nothing.

**2. EKS Auto Mode does not ship a metrics API.** HPAs read resource metrics
from `metrics.k8s.io`, which is served by metrics-server. Auto Mode registers
only `v1.metrics.eks.amazonaws.com` — that backs the console's metrics view and
is **not** a substitute. Verify before applying `hpa.yaml`:

```bash
kubectl top nodes
# "error: Metrics API not available"  -> no metrics-server, HPAs will not scale

kubectl get apiservices | grep metrics.k8s.io
# no output -> same conclusion
```

Without it the HPAs come up but report `<unknown>/70%` for their targets and
never scale. Install metrics-server first if you want working autoscaling:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl top nodes    # should now return values
```

## 🧹 Cleanup

```bash
# Delete the workloads
kubectl delete namespace game-2048
```

> `kubectl delete -f .` would also remove `auto-mode-ingressclass.yaml`, which
> is a **cluster-scoped** resource shared with the KRO deployment. Delete the
> namespace instead unless you intend to remove the IngressClass too.

The DynamoDB tables, S3 bucket and IAM role live outside this namespace and are
not removed by the above.

## 🎯 Recommended Approach

1. **KRO-based deployment** (`kro/README.md`) — provisions AWS resources with
   the application, and is the path the deployment scripts support
2. **GitOps** — the cluster also has a managed Argo CD capability available

See the main [README.md](../README.md) for the complete installation guide.
