
provider "aws" {
  region = local.region
}

provider "kubectl" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.eks_cluster_id]
  }
}

provider "kubernetes" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.eks_cluster_id]
    }
  }
}

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.4.0"

  cluster_name    = local.name
  cluster_version = local.version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  managed_node_groups = {
    mg_5 = {
      node_group_name = "managed-spot"
      instance_types  = local.instance_types
      min_size        = local.min_instance_size
      desired_size    = local.desired_instance_size
      max_size        = local.max_instance_size
      capacity_type   = "SPOT"
      subnet_ids      = module.vpc.private_subnets
    }
  }

  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed

    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  tags = local.tags
  depends_on = [
    module.vpc
  ]
}


#---------------------------------------------------------------
# Kubernetes and EKS addons
#---------------------------------------------------------------

module "eks_kubernetes_addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.4.0"

  eks_cluster_id               = module.eks.eks_cluster_id
  eks_cluster_endpoint         = module.eks.eks_cluster_endpoint
  eks_oidc_provider            = module.eks.oidc_provider
  eks_cluster_version          = module.eks.eks_cluster_version
  eks_worker_security_group_id = module.eks.worker_node_security_group_id

  enable_amazon_eks_coredns = true
  amazon_eks_coredns_config = {
    addon_version     = data.aws_eks_addon_version.latest["coredns"].version
    resolve_conflicts = "OVERWRITE"
  }
  enable_amazon_eks_kube_proxy = true
  amazon_eks_kube_proxy_config = {
    addon_version     = data.aws_eks_addon_version.default["kube-proxy"].version
    resolve_conflicts = "OVERWRITE"
  }
  enable_amazon_eks_vpc_cni            = true
   amazon_eks_vpc_cni_config = {
    addon_version     = data.aws_eks_addon_version.latest["vpc-cni"].version
    resolve_conflicts = "OVERWRITE"
  }
  enable_amazon_eks_aws_ebs_csi_driver = true
  amazon_eks_aws_ebs_csi_driver_config = {
    addon_version     = data.aws_eks_addon_version.latest["aws-ebs-csi-driver"].version
    resolve_conflicts = "OVERWRITE"
  }

  enable_aws_load_balancer_controller = true
  
  tags = local.tags

  depends_on = [
    module.vpc,
    module.eks.managed_node_groups
  ]
}



#---------------------------------------------------------------
# VPC module
#---------------------------------------------------------------
    
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway                             = true
  single_nat_gateway                             = true
  enable_dns_hostnames                           = true
  enable_ipv6                                    = true
  private_subnet_assign_ipv6_address_on_creation = true
  private_subnet_ipv6_prefixes                   = [0, 1, 2]

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = module.eks.configure_kubectl
}