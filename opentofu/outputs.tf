# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = module.vpc.natgw_ids
}

# EKS Outputs
# NOTE: this used to expose module.eks.cluster_id. As of EKS module v21 that
# output is populated only for local clusters on Outposts and is otherwise an
# empty string, which silently broke `aws eks update-kubeconfig --name`.
# The cluster name is what callers actually want.
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

# The EKS-managed cluster security group is the meaningful one under Auto Mode:
# nodes are managed by AWS, so there is no self-managed node security group.
output "eks_cluster_security_group_id" {
  description = "EKS-managed cluster security group (control plane to data plane)"
  value       = module.eks.cluster_primary_security_group_id
}

output "eks_node_iam_role_arn" {
  description = "IAM role used by EKS Auto Mode nodes"
  value       = module.eks.node_iam_role_arn
}

output "eks_capabilities" {
  description = "ARN, version and IAM role of each EKS capability on the cluster"
  value = {
    ack = {
      arn          = module.ack.arn
      version      = module.ack.version
      iam_role_arn = module.ack.iam_role_arn
    }
    kro = {
      arn          = module.kro.arn
      version      = module.kro.version
      iam_role_arn = module.kro.iam_role_arn
    }
  }
}

# NOTE: there is no node-groups output. EKS Auto Mode provisions nodes itself,
# so this cluster has no managed node groups to report. See
# eks_node_iam_role_arn above for the role Auto Mode nodes run as.

output "eks_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if enabled"
  value       = module.eks.oidc_provider_arn
}

# Kubectl configuration command
output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

# Region output
output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

# KRO Information
output "kro_setup_info" {
  description = "Information for setting up KRO (Kubernetes Resource Operator)"
  value = {
    cluster_name      = module.eks.cluster_name
    region            = var.aws_region
    vpc_id            = module.vpc.vpc_id
    private_subnets   = module.vpc.private_subnets
    oidc_provider_arn = module.eks.oidc_provider_arn
  }
}
