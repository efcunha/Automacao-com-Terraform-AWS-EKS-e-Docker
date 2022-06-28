variable "eks_managed_node_groups" {
  type        = map(any)
  description = "Mapa de definições de grupos de nós gerenciados do EKS para criar"
}
variable "autoscaling_average_cpu" {
  type        = number
  description = "Limite médio de CPU para dimensionar automaticamente instâncias do EKS EC2."
}
variable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS."
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