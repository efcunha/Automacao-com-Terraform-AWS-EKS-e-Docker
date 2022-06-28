# for base/network.tf
variable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS."
}
variable "iac_environment_tag" {
  type        = string
  description = "Tag da AWS para indicar o nome do ambiente de cada objeto de infraestrutura."
}
variable "name_prefix" {
  type        = string
  description = "Prefixo a ser usado em cada nome de objeto de infraestrutura criado na AWS."
}
variable "main_network_block" {
  type        = string
  description = "Bloco CIDR base a ser usado em nossa VPC."
}
variable "subnet_prefix_extension" {
  type        = number
  description = "Extensão de bits de bloco CIDR para calcular blocos CIDR de cada sub-rede."
}
variable "zone_offset" {
  type        = number
  description = "Deslocamento de extensão de bits de bloco CIDR para calcular sub-redes públicas, evitando colisões com sub-redes privadas."
}
variable "eks_managed_node_groups" {
  type        = map(any)
  description = "Mapa de definições de grupos de nós gerenciados do EKS a serem criados."
}
variable "autoscaling_average_cpu" {
  type        = number
  description = "Limite médio de CPU para dimensionar automaticamente instâncias do EKS EC2."
}
variable "spot_termination_handler_chart_name" {
  type        = string
  description = "Nome do Helm chart do manipulador de terminação do EKS Spot."
}
variable "spot_termination_handler_chart_repo" {
  type        = string
  description = "Nome do repositório Helm do manipulador de encerramento do EKS Spot."
}
variable "spot_termination_handler_chart_version" {
  type        = string
  description = "Versão do gráfico Helm do manipulador de terminação do EKS Spot."
}
variable "spot_termination_handler_chart_namespace" {
  type        = string
  description = "Namespace do Kubernetes para implantar o gráfico Helm do manipulador de terminação do EKS Spot."
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
  description = "Nome do Helm chart do AWS Load Balancer Controller."
}
variable "alb_controller_chart_repo" {
  type        = string
  description = "Nome do repositório Helm do AWS Load Balancer Controller."
}
variable "alb_controller_chart_version" {
  type        = string
  description = "Versão do gráfico Helm do AWS Load Balancer Controller."
}
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
  description = "Chart de repositório associado ao serviço de DNS externo."
}
variable "external_dns_chart_version" {
  type        = string
  description = "Chart Repo associado ao serviço de DNS externo."
}
variable "external_dns_values" {
  type        = map(string)
  description = "Mapa de valores exigido pelo serviço externo-dns."
}
variable "namespaces" {
  type        = list(string)
  description = "Lista de namespaces a serem criados em nosso cluster EKS."
}
variable "admin_users" {
  type        = list(string)
  description = "Lista de administradores do Kubernetes."
}
variable "developer_users" {
  type        = list(string)
  description = "Lista de desenvolvedores do Kubernetes."
}