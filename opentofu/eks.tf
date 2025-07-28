# EKS using terraform-aws-modules/eks/aws
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Cluster configuration
  enable_cluster_creator_admin_permissions = true
  cluster_enabled_log_types                = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group              = false
  create_cluster_security_group            = false
  create_node_security_group               = false

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    main = {
      name = "${local.name}-node-group"

      instance_types = var.eks_node_instance_types

      min_size     = var.eks_node_min_capacity
      max_size     = var.eks_node_max_capacity
      desired_size = var.eks_node_desired_capacity

      create_launch_template = true
      disk_size              = 50
      ami_type               = "AL2_x86_64"
      capacity_type          = "ON_DEMAND"

      # Node group scaling configuration
      update_config = {
        max_unavailable = 1
      }

      # Kubernetes labels
      labels = {
        Environment = var.environment
        NodeGroup   = "main"
      }

      tags = local.common_tags
    }
  }

  # EKS Addons
  cluster_addons = {
    coredns = {
      most_recent = true
      timeouts = {
        create = "25m"
        delete = "10m"
      }
      configuration_values = jsonencode({
        resources = {
          limits = {
            cpu    = "0.25"
            memory = "256M"
          }
          requests = {
            cpu    = "0.25"
            memory = "256M"
          }
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      preserve    = true
      most_recent = true
      timeouts = {
        create = "25m"
        delete = "10m"
      }
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
        enableNetworkPolicy = "true"
      })
    }
  }

  # Access entries will be managed separately if needed

  # OIDC Identity provider
  cluster_identity_providers = {
    sts = {
      client_id = "sts.amazonaws.com"
    }
  }

  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  tags = local.common_tags
}
# EKS Blueprints Addons
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # AWS Load Balancer Controller
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.6.2"
    repository    = "https://aws.github.io/eks-charts"
    namespace     = "kube-system"
    values = [
      yamlencode({
        clusterName = module.eks.cluster_name
        serviceAccount = {
          create = true
          name   = "aws-load-balancer-controller"
        }
      })
    ]
  }

  # Metrics Server
  enable_metrics_server = true
  metrics_server = {
    chart_version = "3.11.0"
    repository    = "https://kubernetes-sigs.github.io/metrics-server/"
    namespace     = "kube-system"
    values = [
      yamlencode({
        args = [
          "--cert-dir=/tmp",
          "--secure-port=4443",
          "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
          "--kubelet-use-node-status-port",
          "--metric-resolution=15s"
        ]
      })
    ]
  }

  # NGINX Ingress Controller
  enable_ingress_nginx = true
  ingress_nginx = {
    chart_version = "4.8.3"
    repository    = "https://kubernetes.github.io/ingress-nginx"
    namespace     = "ingress-nginx"
    values = [
      yamlencode({
        controller = {
          service = {
            type = "LoadBalancer"
            annotations = {
              "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
              "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
              "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                  = "tcp"
            }
          }
          config = {
            "use-proxy-protocol" = "true"
          }
          metrics = {
            enabled = true
            serviceMonitor = {
              enabled = false
            }
          }
          resources = {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      })
    ]
  }

  tags = local.common_tags
}
# AWS Auth ConfigMap using dedicated module
module "eks_aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"

  manage_aws_auth_configmap = true

  aws_auth_roles = [] # Add your IAM roles here if needed

  aws_auth_users = var.eks_auth_users

  aws_auth_accounts = []

  depends_on = [module.eks]
}
