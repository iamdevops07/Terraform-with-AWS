provider "aws" {
  region = local.region
}

module "staging_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.staging_name
  cidr = local.staging_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.staging_vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_ipv6                                    = true
  private_subnet_assign_ipv6_address_on_creation = true
  private_subnet_ipv6_prefixes                   = [0, 1, 2]

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.staging_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.staging_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.staging_name}-default" }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.staging_name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.staging_tags
}

module "qa_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.qa_name
  cidr = local.qa_vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.qa_vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_ipv6                                    = true
  private_subnet_assign_ipv6_address_on_creation = true
  private_subnet_ipv6_prefixes                   = [0, 1, 2]

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.qa_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.qa_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.qa_name}-default" }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.qa_name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.qa_tags
}

module "mgmt_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.mgmt_name
  cidr = local.mgmt_vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.mgmt_vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.mgmt_vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_ipv6                                    = true
  private_subnet_assign_ipv6_address_on_creation = true
  private_subnet_ipv6_prefixes                   = [0, 1, 2]

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.mgmt_name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.mgmt_name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.mgmt_name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.mgmt_name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.mgmt_name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.mgmt_tags
}


################################################################################
# Transit Gateway Module
################################################################################

module "tgw" {
  source = "terraform-aws-modules/transit-gateway/aws"

  name            = local.tgw_name
  description     = "My TGW shared with several other AWS accounts"
  # When "true" there is no need for RAM resources if using multiple AWS accounts
  enable_auto_accept_shared_attachments = true
  
  transit_gateway_cidr_blocks = ["10.99.0.0/24"]
  # When "true", allows service discovery through IGMP
  enable_mutlicast_support = false

  vpc_attachments = {
    staging_vpc = {
      vpc_id       = module.staging_vpc.vpc_id
      subnet_ids   = module.staging_vpc.private_subnets
      dns_support  = true
      ipv6_support = true

      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false

      tgw_routes = [
        {
          destination_cidr_block = "10.10.0.0/16"
        }
      ]
    },
    qa_vpc = {
      vpc_id     = module.qa_vpc.vpc_id
      subnet_ids = module.qa_vpc.private_subnets
      
      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false

      tgw_routes = [
        {
          destination_cidr_block = "10.20.0.0/16"
        }
      ]
    },
    mgmt_vpc = {
      vpc_id     = module.mgmt_vpc.vpc_id
      subnet_ids = module.mgmt_vpc.private_subnets
      
      transit_gateway_default_route_table_association = false
      transit_gateway_default_route_table_propagation = false

      tgw_routes = [
        {
          destination_cidr_block = "10.30.0.0/16"
        }
      ]
    },
  }

  ram_allow_external_principals = true
  ram_principals                = [307990089504]

  tags = local.qa_tags
}
