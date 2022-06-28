ariable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS."
}
variable "spot_termination_handler_chart_name" {
  type        = string
  description = "Nome do Chart Helm do manipulador de terminação do EKS Spot."
}
variable "spot_termination_handler_chart_repo" {
  type        = string
  description = "Nome do repositório Helm do manipulador de encerramento do EKS Spot."
}
variable "spot_termination_handler_chart_version" {
  type        = string
  description = "Versão do Chart Helm do manipulador de terminação do EKS Spot."
}
variable "spot_termination_handler_chart_namespace" {
  type        = string
  description = "Namespace do Kubernetes para implantar o gráfico Helm do manipulador de terminação do EKS Spot."
}

# cria algumas variáveis
variable "external_dns_iam_role" {
  type        = string
  description = "Nome da função do IAM associado ao serviço de DNS externo."
}
variable "external_dns_chart_name" {
  type        = string
  description = "Nome do gráfico associado ao serviço de DNS externo."
}

variable "external_dns_chart_repo" {
  type        = string
  description = "Gráfico de repositório associado ao serviço de DNS externo."
}

variable "external_dns_chart_version" {
  type        = string
  description = "Chart do repositório associado ao serviço de DNS externo."
}

variable "external_dns_values" {
  type        = map(string)
  description = "Mapa de valores exigido pelo serviço externo-dns."
}

variable "name_prefix" {
  type        = string
  description = "Prefixo a ser usado em cada nome de objeto de infraestrutura criado na AWS."
}
variable "admin_users" {
  type        = list(string)
  description = "Lista de administradores do Kubernetes."
}
variable "developer_users" {
  type        = list(string)
  description = "Lista de desenvolvedores do Kubernetes."
}

variable "dns_hosted_zone" {
  type        = string
  description = "Nome da zona DNS a ser usado do EKS Ingress."
}
variable "load_balancer_name" {
  type        = string
  description = "Nome do serviço do balanceador de carga."
}
variable "alb_controller_iam_role" {
  type        = string
  description = "Nome da função do IAM associado ao serviço do balanceador de carga."
}
variable "alb_controller_chart_name" {
  type        = string
  description = "Nome do gráfico do Helm do AWS Load Balancer Controller."
}
variable "alb_controller_chart_repo" {
  type        = string
  description = "Nome do repositório Helm do AWS Load Balancer Controller."
}
variable "alb_controller_chart_version" {
  type        = string
  description = "Versão do gráfico Helm do AWS Load Balancer Controller."
}

# cria algumas variáveis
variable "namespaces" {
  type        = list(string)
  description = "Lista de namespaces a serem criados em nosso cluster EKS."
}