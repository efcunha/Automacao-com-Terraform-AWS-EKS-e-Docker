# Obtém a zona hospedada de DNS
# ATENÇÃO: se você ainda não possui uma Zona Route53, substitua esses dados por um novo recurso
data "aws_route53_zone" "hosted_zone" {
  name = var.dns_hosted_zone
}

# cria certificado SSL emitido pela AWS
resource "aws_acm_certificate" "eks_domain_cert" {
  domain_name               = var.dns_hosted_zone
  subject_alternative_names = ["*.${var.dns_hosted_zone}"]
  validation_method         = "DNS"

  tags = {
    Name = "${var.dns_hosted_zone}"
  }
}
resource "aws_route53_record" "domain_cert_validation" {
  for_each = {
    for cvo in aws_acm_certificate.eks_domain_cert.domain_validation_options : cvo.domain_name => {
      name   = cvo.resource_record_name
      record = cvo.resource_record_value
      type   = cvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.base_domain.zone_id
}
resource "aws_acm_certificate_validation" "eks_domain_cert_validation" {
  certificate_arn         = aws_acm_certificate.eks_domain_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.domain_cert_validation : record.fqdn]
}

# cria conta de serviço lb Ingress Controller
resource "kubernetes_service_account" "lb_controller" {
  metadata {
    name      = var.load_balancer_name
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = var.load_balancer_name
    }

    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.ingress_gateway_iam_role}"
    }
  }
}

# implanta o Ingress Controller
# https://github.com/kubernetes-sigs/aws-load-balancer-controller/tree/main/helm/aws-load-balancer-controller
resource "helm_release" "ingress_gateway" {
  name       = var.alb_controller_chart_name
  chart      = var.alb_controller_chart_name
  repository = var.alb_controller_chart_repo
  version    = var.alb_controller_chart_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lb_controller.metadata.0.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }
}