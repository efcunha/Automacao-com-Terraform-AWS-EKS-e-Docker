module "base" {
  source = "./base/"

  cluster_name            = var.cluster_name
  name_prefix             = var.name_prefix
  main_network_block      = var.main_network_block
  subnet_prefix_extension = var.subnet_prefix_extension
  zone_offset             = var.zone_offset
  eks_managed_node_groups = var.eks_managed_node_groups
  autoscaling_average_cpu = var.autoscaling_average_cpu
}