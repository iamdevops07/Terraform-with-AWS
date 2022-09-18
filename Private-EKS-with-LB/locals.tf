locals {
  name                  = "eks-with-terraform"
  version               = "1.23"
  region                = "ap-south-1"
  vpc_cidr              = "10.10.0.0/16"
  min_instance_size     = 3
  desired_instance_size = 5
  max_instance_size     = 8
  azs                   = slice(data.aws_availability_zones.available.names, 0, 3)
  node_group_name       = "managed-spot"

  tags = {
    environment = local.name
  }
}