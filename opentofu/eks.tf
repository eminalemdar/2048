# EKS using terraform-aws-modules/eks/aws
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  # v21 dropped the `cluster_` prefix from most inputs.
  name               = local.name
  kubernetes_version = var.eks_cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # The API endpoint defaults to being reachable from anywhere. Restrict
  # cluster_endpoint_public_access_cidrs (or disable public access entirely)
  # before treating this cluster as anything other than disposable.
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  endpoint_private_access      = true

  # Cluster configuration
  enable_cluster_creator_admin_permissions = true
  enabled_log_types                        = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group              = false

  ##############################################################################
  # EKS Auto Mode
  #
  # Enabling compute_config also switches on Auto Mode's managed block storage
  # (EBS CSI) and load balancing (ALB/NLB) — the module derives all three from
  # this one input. That is why there are no managed node groups and no
  # coredns / kube-proxy / vpc-cni add-ons below: Auto Mode ships compute
  # autoscaling, pod and service networking, cluster DNS, block storage and
  # load balancing as core components rather than as add-ons.
  ##############################################################################
  compute_config = {
    enabled    = true
    node_pools = var.eks_auto_mode_node_pools
  }

  # OIDC Identity provider. Kept because the game backend still reaches
  # DynamoDB through IRSA (see kubernetes/kro/iam-rgd.yaml).
  identity_providers = {}

  # IAM principals granted access to the cluster. v21 removed the aws-auth
  # ConfigMap submodule entirely; access entries are now the only mechanism.
  access_entries = var.eks_access_entries

  tags = local.common_tags
}

################################################################################
# EKS Capabilities — AWS-managed platform components that run outside the
# cluster, on EKS-managed infrastructure rather than on your nodes.
#
# These replace the self-managed installs this project used to need:
#   scripts/ack_controller_install.sh  -> module.ack
#   scripts/kro_install.sh             -> module.kro
################################################################################

# AWS Controllers for Kubernetes: manage AWS resources through Kubernetes APIs.
# The RGDs under kubernetes/kro/ create IAM roles, DynamoDB tables and S3
# buckets through the CRDs this capability installs.
module "ack" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.0"

  type         = "ACK"
  cluster_name = module.eks.cluster_name

  # ⚠️  SECURITY WARNING ⚠️
  # The default is AdministratorAccess, which is what the AWS getting-started
  # guide prescribes and what keeps every RGD in this repo working. It also
  # means ACK can create, modify and delete ANY AWS resource in this account.
  #
  # Combined with the kro access policy below, anyone who can create a
  # Kubernetes resource in this cluster can create arbitrary AWS resources.
  #
  # For anything beyond a demo, scope var.ack_iam_role_policies down to the
  # services actually used here (IAM, DynamoDB, S3), or switch to ACK's IAM
  # Role Selectors for per-namespace least privilege.
  iam_role_policies = var.ack_iam_role_policies

  tags = local.common_tags
}

# Kube Resource Orchestrator: composes Kubernetes and AWS resources into the
# higher-level APIs defined in kubernetes/kro/*-rgd.yaml.
#
# kro needs no IAM policies of its own: it never calls AWS APIs, it only
# creates Kubernetes objects.
module "kro" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.0"

  type         = "KRO"
  cluster_name = module.eks.cluster_name

  tags = local.common_tags
}

# Creating the kro capability grants it an access entry carrying
# AmazonEKSKROPolicy, which covers ResourceGraphDefinitions and their instances
# — deliberately NOT the resources an RGD actually produces. Without a broader
# policy an RGD registers its custom API but instantiating one silently creates
# nothing.
#
# ⚠️  SECURITY WARNING ⚠️
# The default is AmazonEKSClusterAdminPolicy, which AWS recommends for getting
# started and covers any RGD this repo defines (Namespaces, Deployments,
# Services, ServiceAccounts, Ingresses and the ACK *.services.k8s.aws CRDs).
# It is cluster-admin. Replace it with custom RBAC scoped to the kinds your
# RGDs actually emit before using this beyond a demo.
resource "aws_eks_access_policy_association" "kro" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.kro.iam_role_arn
  policy_arn    = var.kro_access_policy_arn

  access_scope {
    type = "cluster"
  }
}

# NOTE: the aws-auth ConfigMap module that used to live here has been removed.
# EKS module v21 dropped that submodule, and EKS itself treats the aws-auth
# ConfigMap as legacy. Cluster access is now granted through the
# `access_entries` input on module.eks above — see var.eks_access_entries.
#
# NOTE: the eks-blueprints-addons module has also been removed. It installed
# the self-managed AWS Load Balancer Controller and ingress-nginx; Auto Mode
# provides load balancing natively. See kubernetes/auto-mode-ingressclass.yaml
# for the IngressClass that replaces them.
