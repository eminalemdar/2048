# KRO (Kube Resource Orchestrator) Manifests

This directory contains KRO ResourceGraphDefinitions and instances for deploying the 2048 game with AWS resources managed through Kubernetes.

## 🤔 What is KRO?

**KRO (Kube Resource Orchestrator)** is a Kubernetes operator that enables you to create **custom APIs** for managing complex resource compositions. Think of it as a way to build your own Kubernetes resources that can create and manage multiple other resources as a single unit.

### **Key Concepts:**

**🎯 ResourceGraphDefinition (RGD):**

- A **template** that defines a new Kubernetes API
- Describes what resources should be created and how they relate to each other
- Acts as a **blueprint** for complex resource compositions

**📦 Resource Instances:**

- **Actual deployments** created from ResourceGraphDefinitions
- Contain the specific configuration values for your resources
- Can be customized per environment (dev, staging, prod)

**🔗 Resource Graphs:**

- KRO manages **relationships** between resources
- Handles **dependencies** and **ordering** automatically
- Provides **status tracking** across all managed resources

### **Why Use KRO?**

**🚀 Simplify Complex Deployments:**

- Deploy entire application stacks with a single YAML file
- Manage AWS resources alongside Kubernetes resources
- Handle complex resource dependencies automatically

**🎯 Create Reusable Abstractions:**

- Define once, deploy many times across environments
- Hide complexity behind simple, user-friendly APIs
- Enable self-service deployments for development teams

**📊 Better Operational Visibility:**

- Track status of entire resource compositions
- Get unified view of application and infrastructure health
- Simplify troubleshooting with clear resource relationships

### **KRO vs Other Tools:**

> Verified against upstream releases in **August 2026**. Versions move; re-check
> before relying on any row. Crossplane in particular changed substantially in
> v2 — comparisons written against v1 are no longer accurate.

| | kro | Crossplane | Helm | Kustomize | OpenTofu |
|---|---|---|---|---|---|
| **Latest release** | v0.9.3 | v2.3.4 | v4.2.4 | v5.8.1 | v1.12.5 |
| **Maturity** | 🟡 Pre-1.0, API is `v1alpha1` | 🟢 CNCF **Graduated** (Oct 2025) | 🟢 CNCF Graduated | 🟢 Mature | 🟢 Very mature |
| **Governance** | Kubernetes SIG Cloud Provider subproject | CNCF | CNCF | Kubernetes SIG CLI | Linux Foundation · CNCF Sandbox |
| **License** | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 | MPL 2.0 |
| **Creates custom APIs** | ✅ An RGD generates a CRD | ✅ XRD + Composition | ❌ Templates only | ❌ Overlays only | ❌ External tool |
| **Composes K8s resources** | ✅ | ✅ **Any** K8s resource (new in v2) | ✅ Charts | ✅ Base + overlays | 🟡 Via the Kubernetes provider |
| **Composes cloud resources** | 🟡 Via ACK / KCC / ASO controllers | ✅ Native providers | ❌ | ❌ | ✅ Native providers |
| **Dependency ordering** | ✅ Resolved from the graph | ✅ Composition functions | 🟡 Hooks and weights | ❌ Manual | ✅ Dependency graph |
| **Drift correction** | ✅ Continuous reconciliation | ✅ Continuous reconciliation | 🟡 Only on upgrade | ❌ Only on re-apply | 🟡 Only on apply |
| **Status tracking** | ✅ Aggregated onto the instance | ✅ Per-resource conditions | 🟡 kstatus health (new in v4) | ❌ None | ✅ State file |
| **GitOps** | ✅ Native | ✅ Native | ✅ Via Argo CD / Flux | ✅ Native | 🟡 Needs a runner |
| **Learning curve** | 🟡 Moderate | 🔴 Steep | 🟢 Easy | 🟢 Easy | 🟡 Moderate |
| **Operational overhead** | 🟢 Low — no controller here (EKS Capability) | 🟡 Controllers + providers to run | 🟢 Low | 🟢 Low | 🟡 State backend + runner |

**Choosing between them:** kro and Crossplane overlap most. Crossplane is the
mature choice with a far larger provider ecosystem; kro is smaller and leans on
KRM controllers you already run — which is why it suits this project, where ACK
and kro are both AWS-managed EKS Capabilities with nothing to install. Helm and
Kustomize solve packaging and overlays, not resource composition, so they are
complements rather than alternatives.

## 🎮 KRO in This Project

In our 2048 game project, KRO enables us to:

1. **🗄️ Manage AWS Resources** - Create DynamoDB tables and S3 buckets through Kubernetes
2. **🚀 Deploy Complete Stacks** - Single command deploys infrastructure + application
3. **🌍 Environment Management** - Same definitions, different configurations per environment
4. **🔧 Operational Simplicity** - Use `kubectl` to manage everything
5. **📈 Scale Complexity** - Handle complex resource relationships automatically

## 🏗️ Architecture

KRO enables **Kubernetes-native** management of AWS resources through ResourceGraphDefinitions (RGDs):

```text
┌─────────────────────────────────────┐
│        ResourceGraphDefinitions     │
├─────────────────────────────────────┤
│ • DynamoDB Table RGD                │
│ • S3 Backup Bucket RGD              │
│ • Game2048 Application RGD          │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│           Resource Instances        │
├─────────────────────────────────────┤
│ • DynamoDB leaderboard table        │
│ • S3 backup bucket                  │
│ • Complete 2048 application         │
└─────────────────────────────────────┘
```

## 📁 Directory Structure

```text
kubernetes/kro/
├── README.md                           # This file
├── namespace.yaml                     # The `kro` namespace the instances live in.
│                                      #   The kro capability runs outside the
│                                      #   cluster and does NOT create it.
├── dynamodb-rgd.yaml                  # DynamoDB ResourceGraphDefinition
├── game-sessions-rgd.yaml             # Game sessions table RGD
├── iam-rgd.yaml                       # IAM role for service accounts RGD
├── game2048-app-rgd.yaml             # Application ResourceGraphDefinition
├── s3-rgd.yaml                        # S3 ResourceGraphDefinition (leaderboard backup)
└── instances/
    ├── game2048-leaderboard-table.yaml    # Leaderboard DynamoDB table
    ├── game2048-sessions-table.yaml       # Game sessions DynamoDB table
    ├── game2048-backend-iam-role.yaml     # IAM role for backend
    ├── game2048-app-instance.yaml         # Complete application
    └── s3-instance.yaml                   # S3 backup bucket (leaderboard backup)
```

## 🚀 Prerequisites

Before deploying KRO resources, ensure you have:

1. **EKS Cluster with Auto Mode** deployed with OpenTofu
2. **kro and ACK capabilities** active on that cluster — enabled by the same
   `tofu apply`, nothing to install into the cluster
3. **Auto Mode IngressClass** applied (`kubernetes/auto-mode-ingressclass.yaml`)

> Auto Mode provides load balancing natively, so there is no NGINX Ingress
> Controller and no AWS Load Balancer Controller to install. The `alb`
> IngressClass points at Auto Mode's `eks.amazonaws.com/alb` controller.

### Quick Setup

```bash
# 1. Deploy infrastructure — this also enables the kro and ACK capabilities
../../scripts/deploy_infrastructure.sh

# 2. Confirm both capabilities installed their CRDs
kubectl api-resources | grep kro.run
kubectl api-resources | grep services.k8s.aws

# 3. Deploy the RGDs and instances (also applies the IngressClass)
../../scripts/deploy_kro_application.sh game2048-dev eu-west-1
```

## 🎯 ResourceGraphDefinitions

### 1. IAM Role RGD (`iam-rgd.yaml`)

Creates **IAM roles for service accounts** with:

- **IRSA trust policy** for EKS service accounts, built from the cluster's own
  OIDC provider ID (supplied at deploy time — it is generated per cluster)
- **DynamoDB permissions** scoped to the two tables and their indexes
- **S3 permissions** scoped to the `leaderboard/*` prefix of the backup bucket
- **Proper resource ARNs** for least privilege

**Generated Resources:**

- IAM Role (via ACK IAM controller), with `DynamoDBAccess` and `S3BackupAccess`
  inline policies

> The ACK `Role` resource is created in the **`kro`** namespace
> (`resourceNamespace`), not in the application namespace. The two are separate
> on purpose: an IAM role is a global AWS resource, and tying its custom
> resource to the application namespace created a circular dependency — the role
> could not be created until the namespace existed, but the application needed
> the role.

### 2. DynamoDB Table RGD (`dynamodb-rgd.yaml`)

Creates **DynamoDB tables** with:

- **Primary key**: `id` (String)
- **Global Secondary Index**: `ScoreIndex` — constant partition key
  (`leaderboard`) + `score` sort key, so the backend can `Query` for the top N
  instead of scanning the table
- **Pay-per-request billing** for cost optimization
- **Proper tagging** for resource management

**Generated Resources:**

- DynamoDB Table (via ACK DynamoDB controller)

### 3. Game Sessions RGD (`game-sessions-rgd.yaml`)

Creates **game session storage** with:

- **Simple key schema** for session IDs
- **Pay-per-request billing**
- **Optimized for transient data**

**Generated Resources:**

- DynamoDB Table for game sessions

### 4. Game2048 Application RGD (`game2048-app-rgd.yaml`)

Creates the **complete application stack** with:

- **Backend and Frontend** deployments (2 replicas each)
- **Services** for internal communication
- **ALB Ingress** for external access
- **Service Account** with IAM role annotation
- **Health checks** and resource limits

**Generated Resources:**

- Namespace (`game-2048`)
- Backend Deployment + Service
- Frontend Deployment + Service  
- ALB Ingress with proper routing
- Service Account with IRSA annotation

### 5. S3 Backup RGD (`s3-rgd.yaml`)

Creates **S3 backup storage** with:

- **Versioning** enabled
- **Server-side encryption**
- **Lifecycle policies** for cost optimization
- **Public access blocked**

**Generated Resources:**

- S3 Bucket (via ACK S3 controller)

**How the backend uses it:**

The bucket holds a JSON snapshot of the leaderboard at
`leaderboard/scores.json`. It serves two purposes:

1. **Backup** — rewritten after every accepted score submission. Best effort:
   a failed upload is logged but never fails the submission, because the score
   is already durable in DynamoDB by then.
2. **Read fallback** — if a DynamoDB read *fails*, the backend falls back to the
   S3 snapshot rather than serving an empty leaderboard. The fallback triggers
   on an actual failure, not merely on DynamoDB being unconfigured.

Enabled by `S3_ENABLED=true` and `S3_BUCKET` on the backend (set by the
application RGD). The backend IAM role is granted `s3:GetObject` and
`s3:PutObject` scoped to the `leaderboard/*` prefix only.

## 🚀 Deployment

### Quick Deploy (Recommended)

Follow the main installation guide in the root [README.md](../../README.md#-installation-guide) for the complete step-by-step process.

### Manual Deployment

1. **Deploy ResourceGraphDefinitions:**

   ```bash
   # Deploy all RGDs
   kubectl apply -f iam-rgd.yaml
   kubectl apply -f dynamodb-rgd.yaml
   kubectl apply -f game-sessions-rgd.yaml
   kubectl apply -f s3-rgd.yaml
   kubectl apply -f game2048-app-rgd.yaml
   ```

2. **Wait for RGDs to be ready:**

   ```bash
   kubectl get rgd
   # All should show STATE: Active
   ```

3. **Deploy instances:**

   ```bash
   # Resolve the two account/cluster-specific values first. They are not
   # committed: the account ID should not be published, and the OIDC provider
   # ID is generated per cluster, so any stored value would be stale.
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   export OIDC_PROVIDER_ID=$(aws eks describe-cluster --name game2048-dev \
     --region eu-west-1 --query 'cluster.identity.oidc.issuer' --output text | awk -F/ '{print $NF}')

   # Deploy S3 bucket
   kubectl apply -f instances/s3-instance.yaml

   # Deploy DynamoDB tables
   kubectl apply -f instances/game2048-leaderboard-table.yaml
   kubectl apply -f instances/game2048-sessions-table.yaml

   # Deploy IAM role for backend (needs both placeholders resolved)
   sed -e "s/__AWS_ACCOUNT_ID__/$AWS_ACCOUNT_ID/g" \
       -e "s/__OIDC_PROVIDER_ID__/$OIDC_PROVIDER_ID/g" \
       instances/game2048-backend-iam-role.yaml | kubectl apply -f -

   # Deploy the application (needs the account ID resolved)
   sed -e "s/__AWS_ACCOUNT_ID__/$AWS_ACCOUNT_ID/g" \
       instances/game2048-app-instance.yaml | kubectl apply -f -
   ```

   > **Note:** `scripts/deploy_kro_application.sh` performs these substitutions
   > automatically, and is the recommended path.

4. **Verify deployment:**

   ```bash
   # Check all resources
   kubectl get pods -n game-2048
   kubectl get ingress -n game-2048
   kubectl get tables.dynamodb.services.k8s.aws -n kro
   kubectl get buckets.s3.services.k8s.aws -n kro
   ```

## 🔧 Configuration

### IAM Role Instance Configuration

```yaml
apiVersion: kro.run/v1alpha1
kind: IAMRoleForServiceAccount
metadata:
  name: game2048-backend-iam-role
spec:
  roleName: "game2048-backend-role"
  serviceAccountName: "game2048-backend"
  serviceAccountNamespace: "game-2048"
  region: "eu-west-1"
```

### DynamoDB Instance Configuration

```yaml
apiVersion: kro.run/v1alpha1
kind: DynamoDBTable
metadata:
  name: game2048-leaderboard-dev
spec:
  tableName: "game2048-leaderboard-dev"
  region: "eu-west-1"
  billingMode: "PAY_PER_REQUEST"
```

### Application Instance Configuration

```yaml
apiVersion: kro.run/v1alpha1
kind: Game2048Application
metadata:
  name: game2048-dev
spec:
  name: "game2048"
  namespace: "game-2048"
  backendImage: "emnalmdr/2048-backend:v9"
  backendReplicas: 2
  frontendImage: "emnalmdr/2048-frontend:v9"
  frontendReplicas: 2
  # Container port: the frontend runs unprivileged and cannot bind port 80.
  frontendPort: 8080
  frontendServicePort: 80
  tableName: "game2048-leaderboard-dev"
  region: "eu-west-1"
  ingressClass: "alb"
  # REQUIRED, and the only field with no default — the backend's IRSA
  # annotation is built from it. The committed instance carries the literal
  # __AWS_ACCOUNT_ID__ placeholder, substituted at deploy time (see above).
  accountId: "123456789012"
```

> Every other field has a default in the RGD schema, so a minimal instance needs
> only `accountId`. `kubectl explain game2048application.spec` lists them all.

## 🔍 Monitoring and Troubleshooting

### Check Resource Status

```bash
# ResourceGraphDefinitions are cluster-scoped — no namespace flag
kubectl get rgd

# kro instances (these live in the kro namespace)
kubectl get dynamodbtable,gamesessionstable,iamroleforserviceaccount,s3backupbucket,game2048application -n kro

# Application resources
kubectl get all -n game-2048

# AWS resources (via ACK) — created in the same namespace as their instance
kubectl get tables.dynamodb.services.k8s.aws -n kro
kubectl get buckets.s3.services.k8s.aws -n kro
kubectl get roles.iam.services.k8s.aws -n kro
```

### View Logs

kro and ACK are **EKS Capabilities**: they run on AWS-managed infrastructure
outside your cluster, so there are no controller pods to tail. Their behaviour
surfaces through the status conditions on the resources themselves.

```bash
# Why an RGD is not Active
kubectl get rgd <name> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'

# Why an instance is not ACTIVE
kubectl get <kind> <name> -n kro -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'

# Why an ACK resource has not synced (ACK.ResourceSynced / ACK.Terminal)
kubectl get tables.dynamodb.services.k8s.aws -n kro -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}  {.type}={.status} {.message}{"\n"}{end}{end}'

# Application logs
kubectl logs -n game-2048 -l app.kubernetes.io/component=backend
kubectl logs -n game-2048 -l app.kubernetes.io/component=frontend

# Capability status
aws eks describe-capability --cluster-name <cluster> --region <region> \
  --capability-name <name> --query 'capability.status'
```

### Common Issues

1. **RGD not Active / CRD not created:**
   - Read the conditions, not logs — there are no controller pods (see above):
     `kubectl get rgd <name> -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'`
   - `GraphAccepted=False` is a schema or CEL error. A status field declared as a
     bare type rather than an expression is the usual cause.
   - `KindReady=False` with `breaking changes detected` means the update removed
     or altered a published CRD property. kro refuses that in place — the graph
     still compiles, but the CRD is not updated. Restore the property, or delete
     and recreate the RGD (which deletes every instance and its resources).

2. **Instance ACTIVE but AWS resource missing:**
   - The ACK resource carries the real error. Check `ACK.ResourceSynced` and
     `ACK.Terminal` conditions on it (see the jsonpath under View Logs).
   - `ACK.Terminal=True` will not retry — it usually means an IAM denial or an
     invalid field. Confirm the ACK capability's role can act on that service.

3. **Instances fail with `namespaces "kro" not found`:**
   - The kro capability runs outside the cluster and creates no namespace:
     `kubectl apply -f namespace.yaml`

4. **Application pods not starting:**
   - Check the image tag exists and the nodes can pull it — EKS cannot pull a
     locally built tag.
   - Confirm the ServiceAccount carries `eks.amazonaws.com/role-arn`; a wrong
     `accountId` on the instance produces a role ARN that does not exist, and
     the backend then fails its DynamoDB calls rather than failing to start.
   - Check resource limits and node capacity.

## 🧹 Cleanup

### Remove All Resources

```bash
# Remove instances (in reverse order)
kubectl delete -f instances/game2048-app-instance.yaml
kubectl delete -f instances/game2048-backend-iam-role.yaml
kubectl delete -f instances/game2048-sessions-table.yaml
kubectl delete -f instances/game2048-leaderboard-table.yaml
kubectl delete -f instances/s3-instance.yaml

# Remove ResourceGraphDefinitions
kubectl delete -f game2048-app-rgd.yaml
kubectl delete -f s3-rgd.yaml
kubectl delete -f iam-rgd.yaml
kubectl delete -f game-sessions-rgd.yaml
kubectl delete -f dynamodb-rgd.yaml

# Remove namespace
kubectl delete namespace game-2048
```

### Remove the kro capability (Optional)

kro is an EKS Capability, so it is removed through OpenTofu rather than a
script — delete `module.kro` and `aws_eks_access_policy_association.kro` from
`opentofu/eks.tf` and re-apply, or destroy the whole stack.

```bash
cd ../../opentofu && tofu destroy
```

> Capabilities use `delete_propagation_policy = RETAIN`, so AWS resources ACK
> created are **not** deleted along with the capability.

## 🎯 Benefits of the KRO Approach

- **One API for both layers.** A single `Game2048Application` covers the
  Kubernetes workloads and the AWS resources behind them, so `kubectl` and
  existing RBAC are the only tools needed.
- **Dependencies are ordered for you.** kro resolves the graph — the IAM role is
  created before the ServiceAccount that references it — instead of leaving the
  ordering to a script.
- **Status in one place.** Each instance aggregates the readiness of everything
  it created, and ACK surfaces AWS-side errors as conditions on its own
  resources.
- **Reusable and parameterised.** The same RGD deploys dev and prod by changing
  instance values, and every field except `accountId` has a default.

### Maturity

kro now lives at [`kubernetes-sigs/kro`](https://github.com/kubernetes-sigs/kro)
as a subproject of Kubernetes SIG Cloud Provider, having moved from the original
`kro-run` organisation. Older links and articles still point at the old
location.

It is **pre-1.0** — the API here is `kro.run/v1alpha1` (controller v0.9.2) and
may change between releases. Two limits worth knowing before building on it:

- A published CRD property **cannot be removed** in place; kro rejects the update
  as a breaking change (see Common Issues).
- `v1alpha1` offers no conversion between schema versions, so a breaking RGD
  change means recreating the RGD and its instances.

For a demo this is fine. Pin the kro version and rehearse RGD upgrades before
depending on it for anything long-lived.
