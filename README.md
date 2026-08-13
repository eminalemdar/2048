# 2048 Game

A modern, responsive 2048 game built with React frontend and Go backend, featuring smooth animations, dark/light themes, leaderboard system, and persistent score storage.

## Contents

**Just want to play?** [Running Locally](#-running-locally) needs only Docker.

**Deploying to AWS?** Read [Installation Guide](#-installation-guide) — it is the
one path that is kept current. The two sections after it are alternatives; deploy
one or the other, never both.

| | |
|---|---|
| [🎮 Features](#-features) | What the game does |
| [🏗️ Architecture](#️-architecture) | Stack at a glance |
| [🚀 Running Locally](#-running-locally) | Docker Compose, no AWS account |
| [📋 Installation Guide](#-installation-guide) | **Start here for AWS** — EKS Auto Mode + kro |
| [☁️ AWS Infrastructure Deployment (Manual)](#️-aws-infrastructure-deployment-manual) | OpenTofu by hand, without the script |
| [☸️ Kubernetes Application Deployment (Plain manifests, without kro)](#️-kubernetes-application-deployment-plain-manifests-without-kro) | Alternative to the kro path |
| [🎛️ KRO (Kube Resource Orchestrator) Deployment](#️-kro-kube-resource-orchestrator-deployment) | What kro is and why it is used here |
| [📜 Script Reference](#-script-reference) | Every script and its arguments |
| [🧹 Cleanup](#-cleanup) | Tear down the app and the infrastructure |
| [🔧 Troubleshooting](#-troubleshooting) | Common failures and their checks |
| [🎯 Game Features](#-game-features) | Controls, leaderboard, storage model |
| [🛠️ Development](#️-development) | Running backend and frontend directly |

### Which doc owns what

This file is the entry point and the end-to-end walkthrough. Details live with
the code they describe — when something changes, update it **there** and link to
it from here rather than restating it, which is how the version numbers and
feature claims in this repo drifted apart in the first place.

| Doc | Authoritative for |
|-----|-------------------|
| [opentofu/README.md](opentofu/README.md) | OpenTofu variables and defaults, EKS Capabilities, cost and permissions warnings |
| [kubernetes/README.md](kubernetes/README.md) | Plain-manifest deployment, the DynamoDB/IAM prerequisites it assumes, autoscaling |
| [kubernetes/kro/README.md](kubernetes/kro/README.md) | What kro is, each ResourceGraphDefinition, and what it creates |

## 🎮 Features

- **Smooth tile movements** with polished animations
- **Dark/Light theme** toggle
- **Touch/swipe support** for mobile devices
- **Menu system** with game options and instructions
- **Global leaderboard** with persistent score storage
- **DynamoDB primary storage** with an **S3 snapshot** as backup and read fallback
- **Server-verified scores** — the backend reads the score, move count and
  duration from its own record of the game, so they cannot be forged
- **Score tracking** with game statistics (moves, duration)
- **Responsive design** for all screen sizes

## 🏗️ Architecture

- **Frontend**: React 19 + Vite 8 (plain CSS — no UI framework)
- **Backend**: Go 1.26 with a RESTful API
- **Database**: AWS DynamoDB, with an S3 snapshot for backup and fallback
- **Containerized**: Docker & Docker Compose, multi-arch images, non-root
- **Kubernetes**: EKS with **Auto Mode** — AWS manages compute, networking,
  cluster DNS, block storage and load balancing
- **EKS Capabilities**: **kro** and **ACK** run as AWS-managed capabilities
  outside the cluster — nothing to install, scale or patch

## 🚀 Running Locally

### Local Prerequisites

- Docker and Docker Compose

### Quick Start

```bash
# Clone and run
docker compose up --build

# Access the game
open http://localhost:3000
```

The game will be available at `http://localhost:3000` with:

- Backend API on port 8000
- DynamoDB Local on port 8001

The `dynamodb-init` service creates both DynamoDB tables before the backend
starts, so there is no manual setup step. DynamoDB Local runs in-memory, so
data is discarded when the containers stop.

## 📋 Installation Guide

This guide provides step-by-step instructions for deploying the 2048 game application on AWS using modern Kubernetes tooling.

### Deployment Architecture

The application uses the following components:

- **EKS Cluster with Auto Mode**: AWS manages compute, networking, cluster DNS,
  block storage and load balancing as core components — no node groups and no
  `coredns` / `kube-proxy` / `vpc-cni` add-ons to install or upgrade
- **EKS Capabilities**: kro and ACK run as AWS-managed capabilities *outside*
  the cluster, so there are no controller pods to install, scale or patch
  - **kro**: Kube Resource Orchestrator for resource composition
  - **ACK**: AWS Controllers for Kubernetes (IAM, DynamoDB, S3)
- **ALB**: provisioned by Auto Mode's built-in load balancing
- **DynamoDB**: NoSQL database for game sessions and leaderboard
- **IAM Roles**: Service Account (IRSA) for secure AWS access

> ⚠️ **Security note on the defaults.** The ACK capability role is created with
> `AdministratorAccess` and the kro capability is granted
> `AmazonEKSClusterAdminPolicy`. These are the AWS getting-started defaults and
> they keep every example here working, but together they mean **anyone who can
> create a Kubernetes resource in this cluster can create arbitrary AWS
> resources in the account**. Scope `ack_iam_role_policies` and
> `kro_access_policy_arn` down before using this beyond a demo.

### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) installed
- AWS CLI configured with appropriate credentials
- kubectl installed
- Docker installed (for building images)

### Step 1: Deploy AWS Infrastructure

Deploy the underlying AWS infrastructure (EKS cluster, VPC, IAM roles) using OpenTofu:

```bash
# Use the provided infrastructure deployment script
./scripts/deploy_infrastructure.sh
```

This script will:

- Initialize OpenTofu configuration
- Deploy an **EKS Auto Mode** cluster with its networking
- Enable the **ACK** and **kro** EKS Capabilities
- Set up IAM roles and policies
- Configure kubectl context

### Step 2: Wait for the capabilities to become active

ACK and kro are enabled by Step 1 — there is nothing to install into the
cluster. They run on AWS-managed infrastructure and install their CRDs for you.

```bash
cd opentofu
CLUSTER_NAME=$(tofu output -raw eks_cluster_name)
AWS_REGION=$(tofu output -raw aws_region)
cd ..

# Both should report ACTIVE
for cap in $(aws eks list-capabilities --cluster-name "$CLUSTER_NAME" \
  --region "$AWS_REGION" --query 'capabilities[].name' --output text); do
  echo -n "$cap: "
  aws eks describe-capability --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --capability-name "$cap" --query 'capability.status' --output text
done
```

Verify the CRDs they installed are present:

```bash
kubectl api-resources | grep kro.run             # ResourceGraphDefinition
kubectl api-resources | grep services.k8s.aws    # ACK resource types
```

> **Previously** this step ran `./scripts/ack_controller_install.sh` and
> `./scripts/kro_install.sh` to install in-cluster controllers via Helm. Those
> scripts have been removed — the capabilities replace them entirely.

### Step 3: Deploy the KRO Application

#### Option A: Automated Deployment (Recommended)

Use the automated deployment script that handles proper ordering and waits for resources:

```bash
# Deploy everything with proper dependency management.
# Both arguments are optional and default to game2048-dev / eu-west-1.
./scripts/deploy_kro_application.sh game2048-dev eu-west-1
```

This script will:

- Deploy all ResourceGraphDefinitions (IAM, DynamoDB, Game Sessions, S3, Application) and wait for them to be active
- Deploy application instances in the correct dependency order (S3 bucket → DynamoDB tables → IAM role → Application)
- Wait for each resource to be ready before proceeding
- Verify the deployment with comprehensive health checks (pod readiness, ALB health)
- Provide access information and monitoring commands

#### Option B: Manual Deployment

Deploy resources manually if you prefer step-by-step control:

```bash
# Step 3a: Deploy ResourceGraphDefinitions
kubectl apply -f kubernetes/kro/iam-rgd.yaml
kubectl apply -f kubernetes/kro/dynamodb-rgd.yaml
kubectl apply -f kubernetes/kro/game-sessions-rgd.yaml
kubectl apply -f kubernetes/kro/s3-rgd.yaml
kubectl apply -f kubernetes/kro/game2048-app-rgd.yaml

# Wait for RGDs to be active
kubectl get rgd -n kro
# All should show STATE: Active

# Step 3b: Resolve the account-specific values.
# Two instance files contain __AWS_ACCOUNT_ID__ and __OIDC_PROVIDER_ID__
# placeholders. Neither value is committed: the account ID should not be
# published, and the OIDC provider ID is generated per cluster, so a stored
# value would be wrong for every other cluster.
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export OIDC_PROVIDER_ID=$(aws eks describe-cluster --name game2048-dev \
  --region eu-west-1 --query 'cluster.identity.oidc.issuer' --output text | awk -F/ '{print $NF}')

# Step 3c: Deploy Application Instances
kubectl apply -f kubernetes/kro/instances/s3-instance.yaml
kubectl apply -f kubernetes/kro/instances/game2048-leaderboard-table.yaml
kubectl apply -f kubernetes/kro/instances/game2048-sessions-table.yaml

# These two need the placeholders substituted before they are applied
sed -e "s/__AWS_ACCOUNT_ID__/$AWS_ACCOUNT_ID/g" \
    -e "s/__OIDC_PROVIDER_ID__/$OIDC_PROVIDER_ID/g" \
    kubernetes/kro/instances/game2048-backend-iam-role.yaml | kubectl apply -f -
sed -e "s/__AWS_ACCOUNT_ID__/$AWS_ACCOUNT_ID/g" \
    kubernetes/kro/instances/game2048-app-instance.yaml | kubectl apply -f -

# Check deployment status
kubectl get pods -n game-2048
kubectl get table -n kro
kubectl get bucket -n kro
kubectl get ingress -n game-2048
```

### Step 4: Access the Application

Once deployed, access the application via the ALB ingress:

```bash
# Get the ALB URL
kubectl get ingress game2048-ingress -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

> ⚠️ **Type `http://` explicitly.** The ingress only creates an **HTTP (port 80)**
> listener. Modern browsers try HTTPS first for a bare hostname, so pasting the
> ALB name alone gives "can't reach this site" even though the app is healthy.
>
> To serve HTTPS, request an ACM certificate and add `certificateARNs` to the
> `IngressClassParams` in `kubernetes/auto-mode-ingressclass.yaml`, plus a
> `443` entry in the ingress `listen-ports` annotation.

### 🎉 Installation Complete

Your 2048 game application is now deployed with:

- ✅ **Backend** (2 fixed replicas)
- ✅ **Frontend** (2 fixed replicas behind the ALB)
- ✅ **Persistent leaderboard** (DynamoDB, with an S3 snapshot as backup and
  read fallback)
- ✅ **Secure access** (IRSA — the backend's IAM role is scoped to its two
  tables and the backup bucket's `leaderboard/*` prefix)
- ✅ **High availability** (Multi-AZ deployment)

> **No autoscaling.** Replica counts are fixed at 2. The kro
> `Game2048Application` creates no HorizontalPodAutoscaler, and EKS Auto Mode
> provides no metrics API for one to read, so nothing scales on load. An HPA
> does exist on the plain-manifest path — see
> [kubernetes/README.md](kubernetes/README.md) for what it needs to work.
> (Auto Mode still scales *nodes* to fit the pods; that is not pod autoscaling.)

### Verification

Verify the deployment is working:

```bash
# Check all pods are running
kubectl get pods -n game-2048

# Check AWS resources
kubectl get table -n kro          # DynamoDB tables
kubectl get bucket -n kro         # S3 buckets
kubectl get role.iam.services.k8s.aws -A  # IAM roles

# Test the backend health endpoint
curl http://<ALB-URL>/health

# Test the leaderboard API
curl http://<ALB-URL>/leaderboard/top
```

## ☁️ AWS Infrastructure Deployment (Manual)

For manual infrastructure deployment without the script:

### Deploy Infrastructure

```bash
cd opentofu
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
tofu init
tofu plan
tofu apply
```

### Configure kubectl

```bash
# Use the output command from tofu apply
aws eks --region eu-west-1 update-kubeconfig --name game2048-dev
```

## ☸️ Kubernetes Application Deployment (Plain manifests, without kro)

This is the **alternative** to the kro path in Step 3. It deploys the same
application from plain manifests in `kubernetes/`, for a cluster where you do
not want kro — or when you want to see the raw resources without an
abstraction over them.

> ### ⚠️ Pick one path — do not run both against the same cluster
>
> The two paths deploy the **same application under different resource names**,
> so they do not update or replace one another. Running this one against a
> cluster that already has the kro deployment gives you a **second, parallel
> copy of the app — including a second ALB Ingress, and therefore a second load
> balancer you will be billed for.**
>
> | Resource | kro path (Step 3) | Plain manifests (this section) |
> |----------|-------------------|-------------------------------|
> | Deployments | `game2048-backend`, `game2048-frontend` | `backend-deployment`, `frontend-deployment` |
> | Services | `game2048-backend-service`, `game2048-frontend-service` | `backend-service`, `frontend-service` |
> | Ingress | `game2048-ingress` | `game-2048-ingress` |
>
> Check which one is live before deploying:
>
> ```bash
> kubectl get deploy -n game-2048
> ```
>
> To switch paths, remove the old one first — the cleanest cut is
> `kubectl delete namespace game-2048` (for the kro path, delete the instances
> first, see [Cleanup](#-cleanup)).

### Prerequisites specific to this path

Unlike the kro path, these manifests **only deploy the workloads**. The AWS
resources the backend needs — the two DynamoDB tables, the optional S3 bucket,
and the IRSA role — are *not* created for you. Create them first; see the
"Database Requirements" and "IAM Requirements" sections of
[kubernetes/README.md](kubernetes/README.md).

### Deploy Application

```bash
cd kubernetes
./deploy.sh
```

> **Note**: these manifests now target EKS Auto Mode's ALB, so they require a
> cluster (the old `nginx` IngressClass and `2048.local` host entry are gone).
> `deploy.sh` applies `auto-mode-ingressclass.yaml` before the Ingress for you.

### Access

The names below are the **plain-manifest** names. On the kro path use
`svc/game2048-frontend-service` and ingress `game2048-ingress` instead.

```bash
# Port forward (no ALB needed)
kubectl port-forward -n game-2048 svc/frontend-service 3000:80

# Or via the ALB — remember the http:// prefix
kubectl get ingress game-2048-ingress -n game-2048 \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

> **Autoscaling**: `deploy.sh` also applies `hpa.yaml`. Those HPAs target the
> plain-manifest deployment names, so they are correct for this path only. They
> also require the **metrics API**, which EKS Auto Mode does not provide out of
> the box — without a metrics-server the HPAs report `<unknown>/70%` and never
> scale. See [kubernetes/README.md](kubernetes/README.md#-autoscaling).

## 🎛️ KRO (Kube Resource Orchestrator) Deployment

For a more Kubernetes-native approach to managing AWS resources, you can use KRO instead of traditional Kubernetes manifests.

### What is KRO?

KRO enables you to create **custom Kubernetes APIs** for managing complex resource compositions, including AWS resources through ACK controllers. It provides:

- **Declarative resource management** - Define infrastructure as Kubernetes resources
- **Resource relationships** - Automatic dependency handling and ordering
- **Reusable abstractions** - Create templates for common deployment patterns
- **GitOps ready** - Version control and CI/CD integration

### KRO Prerequisites

None to install. kro and ACK are enabled as **EKS Capabilities** by
`./scripts/deploy_infrastructure.sh` (see `module.kro` and `module.ack` in
`opentofu/eks.tf`) and run on AWS-managed infrastructure. Confirm they are
active:

```bash
kubectl api-resources | grep kro.run
kubectl api-resources | grep services.k8s.aws
```

> This is the **recommended** path. The alternative is the
> "Kubernetes Application Deployment (Plain manifests, without kro)" section
> above. Deploy one or the other, not both — see the warning there.

### Deploy with KRO

```bash
# Deploy ResourceGraphDefinitions and instances
./scripts/deploy_kro_application.sh game2048-dev eu-west-1

# Check deployment status
kubectl get resourcegraphdefinitions      # cluster-scoped, no -n
kubectl get all -n game-2048
```

### KRO Benefits

- **Simplified operations** - Single command deploys infrastructure + application
- **Environment consistency** - Same definitions, different configurations
- **Resource composition** - Manage related resources as a single unit
- **Status tracking** - Built-in monitoring of resource creation and health

See [kubernetes/kro/README.md](kubernetes/kro/README.md) for detailed KRO documentation and comparison with other tools.

## 📜 Script Reference

The following scripts are available to automate deployment tasks:

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/deploy_infrastructure.sh` | Deploy AWS infrastructure (cluster + capabilities) with OpenTofu | `./scripts/deploy_infrastructure.sh` |
| `scripts/deploy_kro_application.sh` | Deploy the RGDs and application instances | `./scripts/deploy_kro_application.sh [cluster-name] [region]` |
| `scripts/cleanup_kro_application.sh` | Remove the application from the cluster | `./scripts/cleanup_kro_application.sh` |
| `scripts/build_and_push.sh` | Build and push multi-arch Docker images | `./scripts/build_and_push.sh [tag]` |
| `scripts/destroy_infrastructure.sh` | Tear down the AWS infrastructure | `./scripts/destroy_infrastructure.sh` |

> The `ack_controller_install.sh`, `ack_controller_cleanup.sh`,
> `kro_install.sh` and `kro_uninstall.sh` scripts have been **removed**. ACK and
> kro are now EKS Capabilities managed in `opentofu/eks.tf`, so there is nothing
> to install into the cluster.

### Script Examples

```bash
# Deploy infrastructure (cluster with Auto Mode + ACK/kro capabilities)
./scripts/deploy_infrastructure.sh

# Deploy the application
./scripts/deploy_kro_application.sh game2048-dev eu-west-1

# Build and push images (tag defaults to the git short SHA)
./scripts/build_and_push.sh v10
```

## 🧹 Cleanup

### Remove Application

#### Option A: Automated Cleanup (Recommended)

```bash
# Remove application with proper dependency management
./scripts/cleanup_kro_application.sh

# Force cleanup without confirmation
./scripts/cleanup_kro_application.sh --force
```

#### Option B: Manual Cleanup

```bash
# Delete application instances (in reverse order)
kubectl delete -f kubernetes/kro/instances/game2048-app-instance.yaml
kubectl delete -f kubernetes/kro/instances/game2048-backend-iam-role.yaml
kubectl delete -f kubernetes/kro/instances/game2048-sessions-table.yaml
kubectl delete -f kubernetes/kro/instances/game2048-leaderboard-table.yaml
kubectl delete -f kubernetes/kro/instances/s3-instance.yaml

# Delete RGDs
kubectl delete -f kubernetes/kro/game2048-app-rgd.yaml
kubectl delete -f kubernetes/kro/s3-rgd.yaml
kubectl delete -f kubernetes/kro/iam-rgd.yaml
kubectl delete -f kubernetes/kro/game-sessions-rgd.yaml
kubectl delete -f kubernetes/kro/dynamodb-rgd.yaml

# Remove namespace
kubectl delete namespace game-2048
```

### Remove Infrastructure

```bash
# Remove AWS infrastructure
cd opentofu
tofu destroy
```

### Remove the Capabilities (Optional)

kro and ACK are EKS Capabilities, not Helm releases — there is nothing to
`helm uninstall`. They are removed by deleting `module.ack` / `module.kro` from
`opentofu/eks.tf` and re-applying, or by `tofu destroy` above.

> ⚠️ Capabilities are created with `delete_propagation_policy = RETAIN`, so AWS
> resources ACK created (DynamoDB tables, the S3 bucket, IAM roles) are **not**
> deleted with the capability. Remove those separately if you want them gone.

## 🔧 Troubleshooting

### Common Issues

**Pods not starting:**

```bash
# Check pod status and logs
kubectl get pods -n game-2048
kubectl logs <pod-name> -n game-2048
```

**DynamoDB permission errors:**

```bash
# Verify IAM role is attached to service account
kubectl get serviceaccount game2048-backend -n game-2048 -o yaml
# Look for eks.amazonaws.com/role-arn annotation
```

**Ingress not accessible:**

```bash
# The IngressClass must exist and point at Auto Mode's controller.
# There is no aws-load-balancer-controller pod to look for — Auto Mode
# provides load balancing itself.
kubectl get ingressclass alb -o jsonpath='{.spec.controller}'
# expected: eks.amazonaws.com/alb

kubectl describe ingress game2048-ingress -n game-2048
```

If the browser says the site is unreachable but `curl http://<ALB>/health`
returns 200, you are hitting the HTTPS-upgrade issue — see Step 4.

**RGD not active:**

```bash
# ResourceGraphDefinitions are cluster-scoped (no -n flag)
kubectl get rgd
kubectl describe rgd <rgd-name>

# A common failure is a status field declared as a bare type:
#   "status fields without expressions are not supported"
# Status fields must be CEL expressions, e.g. ${iamRole.status.ackResourceMetadata.arn}
```

**Instances fail with `namespaces "kro" not found`:**

```bash
# The kro capability runs outside the cluster and creates no namespace.
kubectl apply -f kubernetes/kro/namespace.yaml
```

### Useful Commands

```bash
# Check all resources
kubectl get all -n game-2048

# View application logs
kubectl logs -f -l app.kubernetes.io/name=game2048-backend -n game-2048

# Test backend API
kubectl port-forward svc/game2048-backend-service 8000:8000 -n game-2048
curl http://localhost:8000/health

# Check DynamoDB tables
kubectl get table -n kro
```

## 🎯 Game Features

### Controls

- **Desktop**: Arrow keys to move tiles
- **Mobile**: Swipe to move tiles
- **Goal**: Reach the 2048 tile to win!

### Leaderboard

- **Submit scores** after each game
- **Global rankings** with top 10 players
- **Game statistics** (moves, duration, score)
- **Persistent storage** across sessions

### Storage

- **DynamoDB** — primary store. The leaderboard is read with a `Query` against
  the `ScoreIndex` GSI (constant partition key + `score` sort key), not a table
  scan, and results are paginated.
- **S3 snapshot** — `leaderboard/scores.json` is rewritten after every accepted
  score. If a DynamoDB read *fails*, the backend serves this snapshot instead of
  an empty leaderboard. Enabled with `S3_ENABLED=true` and `S3_BUCKET`.

## 🛠️ Development

`docker compose up --build` is the easiest path — it starts DynamoDB Local and
creates the tables. To run the pieces directly:

### Backend (Go 1.26)

```bash
cd backend
go test -race ./...

# Needs DynamoDB. Point it at DynamoDB Local (docker compose up dynamodb-local
# dynamodb-init) or at real AWS. Without AWS_REGION the API returns 500s —
# by design, rather than panicking.
AWS_REGION=us-east-1 \
DYNAMODB_ENDPOINT=http://localhost:8001 \
DYNAMODB_TABLE=game2048-leaderboard \
GAME_SESSIONS_TABLE=game2048-sessions-dev \
AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
go run .
```

### Frontend (Node 24)

```bash
cd frontend
npm ci
npm run dev     # proxies /game, /leaderboard and /health to localhost:8000
```

The bundle calls the API with relative paths by default, which is what the
single-origin ALB deployment needs. Set `VITE_API_URL` at **build** time to
point at a backend on another origin (docker-compose does this).

---

Enjoy the game! 🎮
