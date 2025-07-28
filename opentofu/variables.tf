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
  default     = "1.28"
}

variable "eks_node_instance_types" {
  description = "Instance types for EKS nodes"
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "eks_node_desired_capacity" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_node_max_capacity" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 4
}

variable "eks_node_min_capacity" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 1
}

variable "eks_auth_users" {
  description = "List of IAM users to add to aws-auth configmap"
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}
