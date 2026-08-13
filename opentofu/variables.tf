variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "game2048"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "172.16.0.0/16"
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server is reachable from the public internet"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = <<-EOT
    CIDR blocks allowed to reach the public EKS API endpoint.
    Defaults to 0.0.0.0/0, which exposes the Kubernetes API to the entire
    internet. Narrow this to your office/VPN ranges for anything but a
    throwaway cluster.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "At least one CIDR must be allowed, or the endpoint is unreachable."
  }
}

# Node sizing variables are gone: EKS Auto Mode provisions and scales nodes
# itself via Karpenter, so there are no instance types or min/max/desired
# counts to set. Use a custom NodePool if you need specific instance shapes.
variable "eks_auto_mode_node_pools" {
  description = <<-EOT
    Built-in EKS Auto Mode node pools to enable.
    'system' hosts critical components, 'general-purpose' hosts workloads.
  EOT
  type        = list(string)
  default     = ["system", "general-purpose"]
}

################################################################################
# EKS Capabilities
################################################################################

variable "ack_iam_role_policies" {
  description = <<-EOT
    IAM policies attached to the ACK capability role, as {name = policy_arn}.

    ⚠️  WARNING: the default is AdministratorAccess. This is what the AWS
    getting-started guide uses and it keeps every RGD in this repo working, but
    it lets ACK create, modify and delete ANY AWS resource in the account.
    Anyone able to create a Kubernetes resource in this cluster can therefore
    create arbitrary AWS resources.

    For real use, scope this to the services actually managed here — IAM,
    DynamoDB and S3 — or adopt ACK IAM Role Selectors for per-namespace
    least privilege.
  EOT
  type        = map(string)
  default = {
    AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
  }
}

variable "kro_access_policy_arn" {
  description = <<-EOT
    EKS access policy associated with the kro capability role so it can manage
    the Kubernetes resources its ResourceGraphDefinitions create.

    ⚠️  WARNING: the default is AmazonEKSClusterAdminPolicy — cluster admin.
    AWS recommends it for getting started and it covers any RGD, but it should
    be replaced with RBAC scoped to the kinds your RGDs actually emit before
    using this beyond a demo.
  EOT
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

variable "eks_access_entries" {
  description = <<-EOT
    EKS access entries granting IAM principals access to the cluster.
    Replaces the legacy aws-auth ConfigMap, which EKS module v21 removed.

    Example:
      {
        developer = {
          principal_arn = "arn:aws:iam::123456789012:user/developer"
          policy_associations = {
            admin = {
              policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
              access_scope = { type = "cluster" }
            }
          }
        }
      }
  EOT
  type        = any
  default     = {}
}
