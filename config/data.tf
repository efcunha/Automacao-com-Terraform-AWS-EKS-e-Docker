data "aws_caller_identity" "current" {} # usado para acessar o ID da conta e o ARN

# obtém a zona hospedada de DNS
# ATENÇÃO: se você ainda não possui uma Zona Route53, substitua esses dados por um novo recurso
data "aws_route53_zone" "hosted_zone" {
  name = var.dns_hosted_zone
}
