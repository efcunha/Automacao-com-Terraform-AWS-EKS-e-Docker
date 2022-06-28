# obtenha todas as AZs disponíveis em nossa região
data "aws_availability_zones" "available_azs" {
  state = "available"
}
