terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chatwoot-batch23-terraform-state"
    key            = "environments/staging/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "chatwoot-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# EIP fixes pour garder des IPs stables entre destroy/apply
resource "aws_eip" "app" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "chatwoot-${var.env}-app-eip" })
}

resource "aws_eip" "monitoring" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "chatwoot-${var.env}-monitoring-eip" })
}

# RÉCUPÉRATION DES AMIs — Récupère automatiquement les dernières AMIs construites avec Packer
data "aws_ami" "bastion" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["bastion-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "chatwoot" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["chatwoot-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "monitoring" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["monitoring-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Networking
module "networking" {
  source = "../../modules/networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = []
  availability_zones   = var.availability_zones
  enable_nat_gateway   = false
  tags                 = var.tags
}

# IAM — Utilisateurs (Terraform/CI) + Rôle EC2 + Profil d'instance
module "iam" {
  source = "../../modules/iam"
  env    = var.env
  tags   = var.tags
}

# SSM Run Command — permet à la CI d'exécuter des commandes sur l'instance
# pour redémarrer rails/sidekiq sans recréer l'instance (pas d'ASG en staging)
resource "aws_iam_role_policy_attachment" "ec2_ssm_run_command" {
  role       = module.iam.ec2_role_name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# GROUPES DE SÉCURITÉ — Inline (spécifiques au staging)
# Ordre de création (pas de dépendance circulaire) :
resource "aws_security_group" "bastion" {
  name        = "chatwoot-${var.env}-bastion-sg"
  description = "SSH only from allowed CIDRs"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port   = 2022
    to_port     = 2022
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Egress SSH vers l'app et le monitoring (pour ProxyJump et tunnels SSH)
  egress {
    from_port   = 2022
    to_port     = 2022
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_cidrs
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-sg" })
}

resource "aws_security_group" "monitoring" {
  name        = "chatwoot-${var.env}-monitoring-sg"
  description = "Prometheus + Grafana - accessible from bastion only"
  vpc_id      = module.networking.vpc_id

  # Grafana (accès depuis le bastion via tunnel SSH ou ProxyJump)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Interface Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # SSH depuis le bastion uniquement
  ingress {
    from_port       = 2022
    to_port         = 2022
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-monitoring-sg" })
}

resource "aws_security_group" "app" {
  name        = "chatwoot-${var.env}-app-sg"
  description = "Chatwoot app - public HTTP, SSH and scraping from bastion/monitoring"
  vpc_id      = module.networking.vpc_id

  # HTTP Chatwoot (accès public)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH depuis le bastion uniquement (ProxyJump, tunnels SSH)
  ingress {
    from_port       = 2022
    to_port         = 2022
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # node_exporter (port 9100) — depuis l'EC2 de monitoring uniquement
  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  # redis_exporter (port 9121) — depuis l'EC2 de monitoring uniquement
  ingress {
    from_port       = 9121
    to_port         = 9121
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-app-sg" })
}


# BASTION
# Point d'entrée SSH unique. ProxyJump vers l'app et le monitoring.
# ssh -J ubuntu@<bastion_ip> ubuntu@<app_ip_privée>
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.bastion.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.key_name
  subnet_id                   = module.networking.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion" })
}


# EC2 APP
# Chatwoot (rails + sidekiq) + PostgreSQL + Redis lancés via Docker Compose.
# ACTIVE_STORAGE_SERVICE=local (pas de S3 en staging).
resource "aws_instance" "app" {
  ami                    = data.aws_ami.chatwoot.id
  instance_type          = var.app_instance_type
  key_name               = var.key_name
  subnet_id              = module.networking.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = module.iam.instance_profile_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-app", Role = "chatwoot" })
}

resource "aws_eip_association" "app" {
  allocation_id = aws_eip.app.id
  instance_id   = aws_instance.app.id
}

# EC2 MONITORING
# Prometheus + Grafana
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.monitoring.id
  instance_type          = var.monitoring_instance_type
  key_name               = var.key_name
  subnet_id              = module.networking.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = module.iam.instance_profile_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-monitoring" })
}

resource "aws_eip_association" "monitoring" {
  allocation_id = aws_eip.monitoring.id
  instance_id   = aws_instance.monitoring.id
}
