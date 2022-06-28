# Cria namespaces no EKS
resource "kubernetes_namespace" "eks_namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    annotations = {
      name = each.key
    }
    name = each.key
  }
}
