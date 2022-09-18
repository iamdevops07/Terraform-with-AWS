data "aws_availability_zones" "available" {}

data "aws_eks_addon_version" "latest" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver"])

  addon_name         = each.value
  kubernetes_version = local.cluster_version
  most_recent        = true
}