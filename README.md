# Automação com Terraform, AWS e Docker 
### Crie um cluster EKS de nível de produção com o Terraform

![Terraform](https://miro.medium.com/max/1400/1*FL83CEzVcducCEP80rGjbg.png)

### Arquitetura:

O Kubernetes tornou-se um dos principais no espaço nativo da nuvem hoje.

É uma ótima implementação para todas as organizações, grandes ou pequenas, mas é um participante importante para quem deseja implantar aplicativos de maneira altamente escalável e segura.

Dada minha experiência pessoal usando Kubernetes, [Terraform](https://www.terraform.io/) e AWS, decidi criar uma implementação que provisionará o cluster EKS usando dois grupos de nós diferentes (spot e sob demanda) e também dividirá a criação e configuração da infraestrutura em diferentes módulos .

Um módulo Terraform que cria recursos VPC e EKS na AWS. Este será o módulo base.

Um módulo do Terraform que configura os componentes do Kubernetes no cluster EKS (controladores de entrada, manipuladores de terminação pontual, DNS externo, namespaces etc.)

### Introdução:

Este artigo demonstra como usar o Terraform para provisionar o Amazon Elastic Kubernetes Service (EKS).

Aproveitaremos os módulos oficiais do [Terraform](https://www.terraform.io/language/modules/sources) para desenvolver alguns desses recursos seguindo as melhores práticas e evitar reinventar a roda.

O cluster será criado em uma zona múltipla.

Vamos usar [Infraestrutura como Código](https://www.terraform.io/) para criar:

- Uma nova VPC com sub-redes públicas e privadas de várias zonas.

- Um único Gateway NAT. Isso pode criar um único ponto de falha, pois o NAT Gateway está em uma AZ. Você pode alterar para garantir a disponibilidade total.

- Um cluster Kubernetes, com uma combinação de instâncias spot e sob demanda do EC2 em execução em sub-redes privadas, com grupo de escalonamento automático baseado no uso médio da CPU.

- Um Application Load Balancer (ALB) para aceitar chamadas HTTP públicas e encaminhá-las para nós do Kubernetes, bem como executar verificações de integridade para dimensionar os serviços do Kubernetes, se necessário.

- Um AWS Load Balancer Controller dentro do cluster, para receber e encaminhar solicitações HTTP do mundo externo para pods do Kubernetes.

- Uma zona DNS com um certificado SSL para fornecer HTTPS para cada serviço do Kubernetes. Usaremos o serviço [DNS externo](https://github.com/kubernetes-sigs/external-dns) para gerenciar a zona do Kubernetes. Você pode ler mais sobre isso.

- Um aplicativo de amostra para implantar em nosso cluster, usando um Helm Chart.

### Pré-requisitos:

Você precisa ter algum conhecimento básico sobre como trabalhar com Kubernetes e criar um cluster EKS usando um console de gerenciamento da AWS ou CLI e conhecimento básico do Terraform.

Você precisará ter:

- Uma conta ativa da AWS. Você pode se inscrever e usar o nível gratuito oferecido pela AWS. Por favor, alguns dos recursos criados não vão além do teste gratuito.

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) e [AWS Vault](https://github.com/99designs/aws-vault) são instalados e configurados em sua máquina local. Eu não vou cobrir como fazer isso aqui. Se você tiver algum problema ao instalar e configurar, por favor, deixe-me saber no comentário. Vou tentar te ajudar.

- Terraform CLI em sua máquina local. Usamos a versão v1.19 neste documento, mas sinta-se à vontade para usar versões mais recentes, se desejar. Minha recomendação é usar uma [docker-imagem](https://hub.docker.com/r/hashicorp/terraform) com um arquivo de composição do docker ou [tfenv](https://github.com/tfutils/tfenv) e simplificar a instalação e o uso de uma versão específica.

- kubectl instalado em sua máquina local


💰 Texto explicativo do orçamento: criar alguns desses recursos, por exemplo, VPC, EKS e DNS, provavelmente trará algum custo ao seu faturamento mensal da AWS, pois alguns recursos podem ir além do teste gratuito.
Portanto, esteja ciente disso antes de aplicar o Terraform! Você também pode certificar-se de destruir imediatamente os recursos assim que terminar este tutorial.

### Provedor de configuração com Terraform:

Após uma breve introdução, vamos entrar em nossa infraestrutura como código! Veremos trechos de configuração do Terraform necessários em cada etapa.
Você pode copiá-los e tentar aplicar esses planos por conta própria.

Começamos criando uma pasta e abrindo a pasta em seu editor favorito.

A primeira coisa que devemos criar é a [configuração do provedor](https://www.terraform.io/language/providers). O Terraform conta com plugins chamados “provedores” para interagir com provedores de nuvem, provedores de SaaS e outras APIs.

As configurações do Terraform devem declarar quais provedores são necessários para que o Terraform possa instalá-los e usá-los.

proveider.tf
```ssh
terraform {
  required_version = "1.1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.11.0" # Opcional, mas recomendado em produção
    }
  }

}
```

✅ Recomendação: É uma boa ideia declarar a versão do Terraform a ser usada para evitar quaisquer alterações que possam afetar nossa infraestrutura se usarmos versões mais recentes/antigas ao executar o Terraform no futuro.

✅ Recomendação: Os provedores de recursos podem ser tratados automaticamente pelo Terraform com o comando init. No entanto, é uma boa ideia defini-los explicitamente usando números de versão da maneira que fizemos acima para evitar alterações de interrupção de fonte de dados/recurso por versões futuras.

✅ Recomendação: A configuração do backend é a [Configuração Parcial](https://www.terraform.io/language/settings/backends/configuration#partial-configuration). Precisamos disso configurado para que possamos ter vários arquivos por ambiente (staging, development, prod) se necessário. Isso nos permitirá ter vários arquivos de estado para cada espaço de trabalho do Terraform:✅ Recommendation: Backend configuration is Partial Configuration. We need this set up so that we can have several files per environment(staging, development, prod) if required. This will enable us to have several state files for each Terraform workspace:

backend.tfvars
```ssh
bucket               = "devops-demo.tfstate"
key                  = "infra.json"
region               = "eu-west-1"
workspace_key_prefix = "environment"
dynamodb_table       = "devops-demo.tfstate.lock"
```

✅ Recomendação: É aconselhável bloquear o [estado](https://www.terraform.io/language/state/locking#state-locking) do seu backend para evitar que outros adquiram o bloqueio e potencialmente corrompam seu estado, especialmente ao executar isso em um pipeline CI/CD. Estamos usando o Amazon [DynamoDB](https://aws.amazon.com/dynamodb/?trk=2431813f-f7fb-4215-a32b-dc6bb102214d&sc_channel=ps&sc_campaign=acquisition&sc_medium=ACQ-P|PS-GO|Brand|Desktop|SU|Database|DynamoDB|EEM|EN|Text|Non-EU&s_kwcid=AL!4422!3!536452473269!e!!g!!aws%20dynamodb&ef_id=Cj0KCQjw2MWVBhCQARIsAIjbwoPpmxOYkOtYKyWGe7vK495lxUp9J2QS_gWIYWnmmrYQuXAg9oIoDNIaAsbnEALw_wcB:G:s&s_kwcid=AL!4422!3!536452473269!e!!g!!aws%20dynamodb) para isso.

⚠️Importante: o bucket do S3 e a tabela do DynamoDB precisam existir antes de executar o comando terraform init. Eles não serão criados pelo Terraform se não existirem na AWS. Você pode criar um bucket manualmente ou por meio de uma ferramenta CI/CD executando um comando como este:

```ssh
aws s3 mb s3://my-iac-bucket-name --region eu-west-1
```

Os nomes dos buckets devem ser exclusivos. Leia mais [aqui](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingBucket.html).

Para a tabela do DynamoDB, a maneira mais rápida de fazer isso é criá-la manualmente, mas você também pode criá-la por meio da AWS CLI.

✅ Recomendação: Evite definir credenciais da AWS em blocos de provedores. Em vez disso, poderíamos usar [variáveis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#environment-variables) de ambiente para essa finalidade.

O Terraform os usará automaticamente para autenticar em APIs da AWS.

Usaremos o docker com este arquivo docker-compose para executar nossos comandos do Terraform.

docker-compose.yml
```ssh
version: '3.7'

services:
  terraform:
    image: hashicorp/terraform:1.1.9
    volumes:
      - .:/infra
    working_dir: /infra
    environment:
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}
```

Como mencionamos acima, usaremos o aws-vault para armazenar e acessar com segurança as credenciais da AWS em nosso ambiente de desenvolvimento.

⚠️Importante: A versão da imagem do docker usada no arquivo docker-compose deve ser a mesma versão do Terraform que estamos usando na configuração do provedor.

Como mencionamos acima, usaremos o [Terraform Workspaces](https://www.terraform.io/language/state/workspaces), por exemplo, o espaço de trabalho de desenvolvimento para implantação no servidor de desenvolvimento.

Para inicializar cada workspace, devemos executar este comando:

```ssh
docker-compose -f docker-compose.yml run --rm terraform init -backend-config=config-backend.tfvars
docker-compose -f docker-compose.yml run --rm terraform workspace new development
```

Com este workspace, se quisermos executar comandos do Terraform no mesmo workspace ou alternar o workspace, podemos fazer isso executando este comando:

```ssh
docker-compose -f docker-compose.yaml run --rm terraform init -backend-config=config-backend.tfvars
docker-compose -f docker-compose.yml run --rm terraform workspace select development
```

Até este ponto, estamos prontos para começar a escrever nossa infraestrutura como código 😀. 

### Faça uma pausa e pegue um café ☕️.

Vamos começar a codificar nosso módulo base. 

Começaremos com a criação da VPC

### Criação de componentes de rede e VPC

Vamos começar criando uma nova [VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html) e todos os componentes de rede necessários (sub-redes, [NAT](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html), [Elastic IP](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html) etc) para isolar nossos recursos relacionados ao EKS em um local seguro.

Para isso, usamos o [módulo terraform oficial](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest) da AWS VPC. Estaremos usando a v3.14.0, que é a versão mais recente do módulo no momento em que escrevemos isso. Sinta-se à vontade para mudar isso.

data.tf
```ssh
data "aws_availability_zones" "available_azs" {
  state = "available"
}
```

network.tf
```ssh
# Reserve Elastic IP para ser usado em nosso gateway NAT
resource "aws_eip" "nat_gw_eip" {
  vpc = true

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

# Criar VPC usando o módulo oficial de VPC da AWS
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.0"

  name = "${var.name_prefix}-vpc"
  cidr = var.main_network_block
  azs  = data.aws_availability_zones.available_azs.names

  private_subnets = [
    # this loop will create a one-line list as ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20", ...]
    # with a length depending on how many Zones are available
    for zone_id in data.aws_availability_zones.available_azs.zone_ids :
    cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) - 1)
  ]

  public_subnets = [
    # this loop will create a one-line list as ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20", ...]
    # with a length depending on how many Zones are available
    # there is a zone Offset variable, to make sure no collisions are present with private subnet blocks
    for zone_id in data.aws_availability_zones.available_azs.zone_ids :
    cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) + var.zone_offset - 1)
  ]

  enable_nat_gateway     = true
   # ative o Gateway NAT único para economizar algum dinheiro. Isso pode criar um único ponto de falha, pois estamos criando um Gateway NAT em apenas uma AZ
   # sinta-se à vontade para alterar essas opções se precisar garantir a disponibilidade total
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true
  reuse_nat_ips          = true
  external_nat_ip_ids    = [aws_eip.nat_gw_eip.id]

  # adicionar tags de VPC/sub-rede exigidas pelo EKS
  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# Cria grupo de segurança para ser usado posteriormente pelo ALB de entrada
resource "aws_security_group" "alb" {
  name   = "${var.name_prefix}-alb"
  vpc_id = module.vpc.vpc_id

  ingress {
    description      = "http"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "https"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    "Name" = "${var.name_prefix}-alb"
  }
}


  private_subnets = [
    for zone_id in data.aws_availability_zones.available_azs.zone_ids :
    cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) - 1)
  ]

  public_subnets = [
    for zone_id in data.aws_availability_zones.available_azs.zone_ids :
    cidrsubnet(var.main_network_block, var.subnet_prefix_extension, tonumber(substr(zone_id, length(zone_id) - 1, 1)) + var.zone_offset - 1)
  ]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
  enable_dns_hostnames   = true
  reuse_nat_ips          = true
  external_nat_ip_ids    = [aws_eip.nat_gw_elastic_ip.id]


  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}
resource "aws_security_group" "alb" {
  name   = "${var.name_prefix}-alb"
  vpc_id = module.vpc.vpc_id

  ingress {
    description      = "http"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "https"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    "Name" = "${var.name_prefix}-alb"
  }
}
```

Criaremos uma nova VPC com sub-redes em cada zona de disponibilidade com um único gateway NAT.

Estamos usando um único gateway NAT aqui para economizar custos, mas lembre-se de que isso pode criar um único ponto de falha. Você pode alterar as opções se precisar garantir a disponibilidade total criando NAT em cada uma das zonas de disponibilidade.

Também estamos adicionando algumas das tags [exigidas pelo EKS](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html).

### Criação de cluster EKS

O próximo componente que vamos criar é um novo cluster Kubernetes.

Estamos usando o [módulo terraform oficial](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest) do AWS EKS.

Estaremos usando v18.21.0 com ~>(Verifique a [sintaxe de restrições de versão](https://www.terraform.io/language/expressions/version-constraints#version-constraint-syntax)), que é a versão mais recente do módulo no momento em que escrevemos isso. Sinta-se à vontade para mudar isso.

eks.tf
```ssh
module "eks-cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.20.2"

  cluster_name                    = var.cluster_name
  cluster_version                 = "1.22"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true
  subnet_ids                      = module.vpc.private_subnets
  vpc_id                          = module.vpc.vpc_id
  eks_managed_node_groups         = var.eks_managed_node_groups

  node_security_group_additional_rules = {
    # Se você omitir isso, receberá um erro interno: falha ao chamar o webhook, o servidor não pôde encontrar o recurso solicitado
    # https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/2039#issuecomment-1099032289
    ingress_allow_access_from_control_plane = {
      type                          = "ingress"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      source_cluster_security_group = true
      description = "Allow access from control plane to webhook port of AWS load balancer controller"
    }
    # permite conexões do grupo de segurança ALB
    ingress_allow_access_from_alb_sg = {
      type                     = "ingress"
      protocol                 = "-1"
      from_port                = 0
      to_port                  = 0
      source_security_group_id = aws_security_group.alb.id
    }
    # permite conexões do EKS com a internet
    egress_all = {
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
    # permite conexões internas de EKS para EKS
    ingress_self_all = {
      protocol  = "-1"
      from_port = 0
      to_port   = 0
      type      = "ingress"
      self      = true
    }
  }
}

# Função do IAM para AWS Load Balancer Controller e anexar ao EKS OIDC
# https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/latest/submodules/iam-role-for-service-accounts-eks
module "eks_ingress_iam" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.22.0"

  role_name                              = "load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.cluster.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Função do IAM para DNS externo e anexar ao EKS OIDC
# https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/latest/submodules/iam-role-for-service-accounts-eks
module "eks_external_dns_iam" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.22.0"

  role_name                     = "external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    main = {
      provider_arn               = module.cluster.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

# Definir frota spot e política de escalonamento automático sob demanda
resource "aws_autoscaling_policy" "eks_autoscaling_policy" {
  count = length(var.eks_managed_node_groups)

  name                   = "${module.cluster.eks_managed_node_groups_autoscaling_group_names[count.index]}-autoscaling-policy"
  autoscaling_group_name = module.cluster.eks_managed_node_groups_autoscaling_group_names[count.index]
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.autoscaling_average_cpu
  }
}
```

asg.tf
```ssh
resource "aws_autoscaling_policy" "eks_autoscaling_policy" {
  count = length(var.eks_managed_node_groups)

  name                   = "${module.cluster.eks_managed_node_groups_autoscaling_group_names[count.index]}-autoscaling-policy"
  autoscaling_group_name = module.cluster.eks_managed_node_groups_autoscaling_group_names[count.index]
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.autoscaling_average_cpu
  }
}
```

Estamos criando o EKS Cluster que usa o EC2 Autoscaling Group for Kubernetes. O EC2 é composto por instâncias spot e sob demanda com escalonamento automático para cima/para baixo com base no uso médio da CPU.

### Definir funções do IAM

Precisamos definir algumas funções do IAM para Load Balancer Controller e DNS externo e anexá-las ao [EKS OIDC](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts-technical-overview.html) como mencionamos no início. Estamos usando o [módulo Função do IAM](https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/latest/submodules/iam-role-for-service-accounts-eks) para conta de serviço para fazer isso.

iam.tf
```ssh
# cria a função do IAM para o AWS Load Balancer Controller e anexa ao EKS OIDC
module "eks_ingress_iam" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.22.0"

  role_name                              = "load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.cluster.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# cria a função do IAM para DNS externo e anexa ao EKS OIDC
module "eks_external_dns_iam" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 4.22.0"

  role_name                     = "external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    ex = {
      provider_arn               = module.cluster.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}
```

Como você pode ver, esses blocos do Terraform usam algumas variáveis. Precisamos definir e criar seus valores correspondentes.

variables.tf
```ssh
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
```

Agora que temos nosso módulo base pronto, estamos prontos para criar nosso cluster EKS. Antes de podermos aplicar isso, precisamos definir alguns valores para essas variáveis.

base-develop,emt.tfvars
```ssh
cluster_name            = "devops-demo-eks-cluster"
iac_environment_tag     = "development"
name_prefix             = "devops-demo-development"
main_network_block      = "10.0.0.0/16"
subnet_prefix_extension = 4
zone_offset             = 8

autoscaling_average_cpu = 30
eks_managed_node_groups = {
  "devops-eks-spot" = {
    ami_type     = "AL2_x86_64"
    min_size     = 1
    max_size     = 16
    desired_size = 1
    instance_types = [
      "t3.medium",
    ]
    capacity_type = "SPOT"
    network_interfaces = [{
      delete_on_termination       = true
      associate_public_ip_address = true
    }]
  }
  "devops-eks-ondemand" = {
    ami_type     = "AL2_x86_64"
    min_size     = 1
    max_size     = 16
    desired_size = 1
    instance_types = [
      "t3.medium",
    ]
    capacity_type = "ON_DEMAND"
    network_interfaces = [{
      delete_on_termination       = true
      associate_public_ip_address = true
    }]
  }
}
```

Neste ponto, podemos organizar todas essas configurações em um módulo e, em seguida, executar os comandos de fluxo de trabalho do Terraform.

main.tf
```ssh
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
```

A primeira coisa a fazer é ter certeza de que estamos no workspace correto e validar nossa configuração executando os seguintes comandos:

```ssh
docker-compose -f docker-compose.yaml run --rm terraform workspace select development
docker-compose -f docker-compose.yaml run --rm terraform validate
```

Depois disso, obtemos a saída do nosso plano executando o seguinte comando.

```ssh
docker-compose -f docker-compose.yaml run --rm terraform plan -out=development.tfplan -var-file=base-network-development.tfvars
```

Isso deve imprimir a saída do plano e nos fornecer os detalhes do que nossa configuração fornecerá quando aplicarmos.

Com tudo parecendo bem, podemos aplicar a saída do plano executando o seguinte comando:

```ssh
docker-compose -f docker-compose.yaml run --rm terraform apply development.tfplan
```

Feito a aplicação, temos um novo cluster EKS na AWS. Agora que terminamos de criar o cluster, podemos prosseguir com a configuração do cluster.

⚠️Importante: Se você quiser fazer uma pausa neste momento ou não quiser deixar a infraestrutura funcionando antes de passar para a próxima etapa, você pode destruir toda a infraestrutura executando os seguintes comandos:

```ssh
docker-compose -f docker-compose.yaml run --rm terraform destroy -var-file=base-network-development.tfvars
```

Dica: Se você não quiser digitar yes ou confirmar toda vez que executar os comandos apply/destroy, você pode adicionar -auto-approve no final desses comandos.

### Configuração do cluster EKS

Como mencionamos no início, usaremos um módulo diferente para configurar o cluster. Buscaremos os dados do EKS Cluster usando a [fonte de dados](https://www.terraform.io/language/data-sources) Terraform.

Primeiro criamos o arquivo de configuração do provedor que inclui todos os provedores necessários (AWS, kubernetes, helm etc).

version.tf
```ssh
terraform {
  required_version = "1.1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.5.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.7.2"
    }
  }
}
```

eks.tf
```ssh
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
```

Nesta configuração, estamos fazendo duas coisas principais:

- Estamos recebendo nosso cluster EKS existente como fonte de dados. Precisamos disso para configurar [Kubernetes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs) e [Helm](https://registry.terraform.io/providers/hashicorp/helm/latest/docs) Terraform Providers.

- Estamos implantando o Helm Chart para o [AWS Node Termination Handler](https://github.com/aws/aws-node-termination-handler) para instâncias spot do EC2, que cuida da realocação de objetos do Kubernetes quando as [instâncias spot são interrompidas](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html).

### Acesso ao IAM

A próxima etapa é configurar o acesso ao IAM necessário para usuários da AWS que entram em nosso cluster EKS usando o [ConfigMap](https://docs.aws.amazon.com/eks/latest/userguide/add-user-role.html) aws-auth.

data.tf
```ssh
data "aws_caller_identity" "current" {} # used for accesing Account ID and ARN
```

iam.tf
```ssh
# Crie mapas de usuários de administradores e desenvolvedores
locals {
  admin_user_map_users = [
    for admin_user in var.admin_users :
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${admin_user}"
      username = admin_user
      groups   = ["system:masters"]
    }
  ]
  developer_user_map_users = [
    for developer_user in var.developer_users :
    {
      userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${developer_user}"
      username = developer_user
      groups   = ["${var.name_prefix}-developers"]
    }
  ]
}

# Add 'mapUsers' section to 'aws-auth' configmap with Admins & Developers
resource "time_sleep" "wait" {
  create_duration = "180s"
  triggers = {
    cluster_endpoint = data.aws_eks_cluster.cluster.endpoint
  }
}
resource "kubernetes_config_map_v1_data" "aws_auth_users" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapUsers = yamlencode(concat(local.admin_user_map_users, local.developer_user_map_users))
  }

  force = true

  depends_on = [time_sleep.wait]
}

# Crie uma função de desenvolvedor usando o RBAC
resource "kubernetes_cluster_role" "iam_roles_developers" {
  metadata {
    name = "${var.name_prefix}-developers"
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods", "pods/log", "deployments", "ingresses", "services"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["*"]
    resources  = ["pods/portforward"]
    verbs      = ["*"]
  }
}

# Vincule os usuários do desenvolvedor com sua função
resource "kubernetes_cluster_role_binding" "iam_roles_developers" {
  metadata {
    name = "${var.name_prefix}-developers"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "${var.name_prefix}-developers"
  }

  dynamic "subject" {
    for_each = toset(var.developer_users)

    content {
      name      = subject.key
      kind      = "User"
      api_group = "rbac.authorization.k8s.io"
    }
  }
}
```

### Load Balancer

A próxima coisa que estamos criando é um [Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html) (ALB) para lidar com solicitações HTTP para nossos serviços. 

Usaremos o serviço AWS Load Balancer Controller implantado usando o Helm.

ingress.tf
```ssh
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
```

Na definição acima, usamos um novo certificado SSL emitido pela AWS para fornecer HTTPS em nosso ALB para ser colocado na frente de nossos pods do Kubernetes. Também definimos algumas anotações exigidas pelo serviço [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/).

⚠️ Observação: esta configuração usa uma fonte de dados para buscar uma zona DNS hospedada no Route53 criada fora desta configuração do Terraform. Se você ainda não tiver um, poderá alterá-lo livremente para criar novos recursos de DNS.

### DNS externo

O próximo componente a ser implantado é o serviço [DNS externo](https://github.com/kubernetes-sigs/external-dns) que será responsável por sincronizar nossos serviços e entradas expostos do Kubernetes e gerenciar nossos registros do Route53.

external-dns.tf
```ssh
# deploy 'external-dns' service
# https://github.com/kubernetes-sigs/external-dns
resource "helm_release" "external_dns" {
  name       = var.external_dns_chart_name
  chart      = var.external_dns_chart_name
  repository = var.external_dns_chart_repo
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  dynamic "set" {
    for_each = var.external_dns_values

    content {
      name  = set.key
      value = set.value
      type  = "string"
    }
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.external_dns_iam_role}"
  }

  # fará com que o ExternalDNS veja apenas as zonas hospedadas correspondentes ao domínio fornecido, omitirá o processamento de todas as zonas hospedadas disponíveis
  set {
    name  = "domainFilters"
    value = "{${var.dns_hosted_zone}}"
  }

  set {
    name  = "txtOwnerId"
    value = data.aws_route53_zone.base_domain.zone_id
  }
}
```

O Helm chart de comando de DNS externo do Kubernetes requer algumas anotações para o novo [certificado ACM](https://docs.aws.amazon.com/acm/latest/userguide/acm-overview.html) gerado para fornecer conexões SSL e também para criar/modificar/excluir registros no domínio base do Route53.

### Namespaces do Kubernetes (opcional)

Agora terminamos de criar os componentes obrigatórios. Para manter nossa implantação limpa e separada, podemos definir alguns namespaces do Kubernetes para nos ajudar a ter melhor gerenciamento e visibilidade em nosso cluster.

namespaces.tf
```ssh
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
```

A parte final é definir a variável necessária para essas configurações e seus valores.

variables.tf
```ssh
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
```

config-developement.tfvars
```ssh
spot_termination_handler_chart_name      = "aws-node-termination-handler"
spot_termination_handler_chart_repo      = "https://aws.github.io/eks-charts"
spot_termination_handler_chart_version   = "0.18.1"
spot_termination_handler_chart_namespace = "kube-system"


external_dns_iam_role      = "external-dns"
external_dns_chart_name    = "external-dns"
external_dns_chart_repo    = "https://kubernetes-sigs.github.io/external-dns/"
external_dns_chart_version = "1.9.0"

external_dns_values = {
  "image.repository"   = "k8s.gcr.io/external-dns/external-dns",
  "image.tag"          = "v0.11.0",
  "logLevel"           = "info",
  "logFormat"          = "json",
  "triggerLoopOnEvent" = "true",
  "interval"           = "5m",
  "policy"             = "sync",
  "sources"            = "{ingress}"
}

admin_users     = ["calvine-otieno", "jannet-kioko"]
developer_users = ["elvis-kariuki", "peter-donald"]

dns_hosted_zone = "calvineotieno.com"
load_balancer_name       = "aws-load-balancer-controller"
alb_controller_iam_role      = "load-balancer-controller"
alb_controller_chart_name    = "aws-load-balancer-controller"
alb_controller_chart_repo    = "https://aws.github.io/eks-charts"
alb_controller_chart_version = "1.4.1"

namespaces = ["dev"]
```

Por favor, altere o valor do dns_base_domain para um domínio que você possui e tem acesso.

⚠️Observação: os usuários do IAM exibidos acima não são reais. Você precisa alterá-los/personalizá-los de acordo com os grupos de usuários em sua conta da AWS. Esses nomes de usuário não precisam existir como identidades do AWS IAM no momento em que você está criando o cluster, pois eles ficarão apenas dentro do cluster do Kubernetes. Leia mais [aqui](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html#create-kubeconfig-automatically) para saber como a AWS CLI lida com a correlação de nome de usuário do IAM/Kubernetes.

Agora que terminamos de criar todas as configurações necessárias, vamos agrupá-las em um módulo. Primeiro, precisamos criar a configuração do provedor e o manifesto de dados.

versions.tf
```ssh
terraform {
  required_version = "1.1.9"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.5.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.7.2"
    }
  }
}


provider "aws" {
  region = "eu-west-1"
  default_tags {
    tags = {
      iac_environment = var.iac_environment_tag
    }
  }
}
```

data.tf
```ssh
data "aws_caller_identity" "current" {} # used for accesing Account ID and ARN
```

Veja como é o módulo principal:

main.tf
```ssh
# módulo para criar o cluster
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

# módulo para configurar o cluster
module "config" {
  source = "./config/"

  cluster_name                             = module.base.cluster_id
  spot_termination_handler_chart_name      = var.spot_termination_handler_chart_name
  spot_termination_handler_chart_repo      = var.spot_termination_handler_chart_repo
  spot_termination_handler_chart_version   = var.spot_termination_handler_chart_version
  spot_termination_handler_chart_namespace = var.spot_termination_handler_chart_namespace
  dns_hosted_zone                          = var.dns_hosted_zone
  load_balancer_name                       = var.load_balancer_name
  alb_controller_iam_role                  = var.alb_controller_iam_role
  alb_controller_chart_name                = var.alb_controller_chart_name
  alb_controller_chart_repo                = var.alb_controller_chart_repo
  alb_controller_chart_version             = var.alb_controller_chart_version
  external_dns_iam_role                    = var.external_dns_iam_role
  external_dns_chart_name                  = var.external_dns_chart_name
  external_dns_chart_repo                  = var.external_dns_chart_repo
  external_dns_chart_version               = var.external_dns_chart_version
  external_dns_values                      = var.external_dns_values
  namespaces                               = var.namespaces
  name_prefix                              = var.name_prefix
  admin_users                              = var.admin_users
  developer_users                          = var.developer_users
}
```

E também as variáveis necessárias:

variables.tf
```ssh
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
```

Agora estamos prontos para executar os comandos do terraform. Selecione a área de trabalho.

Antes de executarmos o plano e aplicarmos os comandos, precisamos formatar e validar nossa configuração para garantir que ela esteja em formato e estilo canônicos e válida.
```ssh
docker-compose -f docker-compose.yaml run --rm terraform fmt
docker-compose -f docker-compose.yaml run --rm terraform validate
```
Após a confirmação de que tudo está correto, agora vamos planejar e aplicar
```ssh
docker-compose -f docker-compose.yaml run --rm terraform plan -out=development.tfplan -var-file=base-development.tfvars -var-file=config-development.tfvars
docker-compose -f docker-compose.yaml run --rm terraform apply development.tfplan
```
Neste ponto, temos um cluster EKS de nível de produção. 

O cluster agora está pronto para hospedar aplicativos.

### É isso por enquanto. 

Quando você terminar e não quiser deixar o cluster EKS em execução, o que eu recomendo para evitar ser cobrado pela AWS, você pode primeiro acionar o trabalho de desinstalação do HELM e, em seguida, acionar o trigger de destruição.