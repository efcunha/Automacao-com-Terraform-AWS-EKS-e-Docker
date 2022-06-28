# Obtenha informações do cluster EKS para configurar provedores Kubernetes e Helm
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}
data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Obtenha autenticação EKS para poder gerenciar objetos k8s do Terraform
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Deploy spot termination handler
resource "helm_release" "spot_termination_handler" {
  name          = var.spot_termination_handler_chart_name
  chart         = var.spot_termination_handler_chart_name
  repository    = var.spot_termination_handler_chart_repo
  version       = var.spot_termination_handler_chart_version
  namespace     = var.spot_termination_handler_chart_namespace
  wait_for_jobs = true
}