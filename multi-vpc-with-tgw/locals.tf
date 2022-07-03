locals {
  tgw_name          = "mutli-vpc-tgw"
  staging_name      = "staging"
  mgmt_name         = "mangement"
  qa_name           = "qa"
  region            = "us-east-1"

  staging_vpc_cidr  = "10.10.0.0/16"
  qa_vpc_cidr       = "10.20.0.0/16"
  mgmt_vpc_cide     = "10.30.0.0/16"
  azs               = slice(data.aws_availability_zones.available.names, 0, 3)
  
  staging_tags = {
    environment = local.staging_name
  }
  qa_tags = {
    environment = local.qa_name
  }

}
