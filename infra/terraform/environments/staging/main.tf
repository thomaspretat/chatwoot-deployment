terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chatwoot-terraform-state"
    key            = "environments/staging/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "chatwoot-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ─────────────────────────────────────────────────────────────────────────────
# MODULE PARTAGÉ — Networking
# ─────────────────────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = [] # Pas de subnet privé en staging
  availability_zones   = var.availability_zones
  enable_nat_gateway   = false # EC2 en public subnet, accès Internet via IGW
  tags                 = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS — Inline (staging-specific)
#
# Ordre de création (pas de dépendance circulaire) :
#   1. bastion_sg  — pas de référence à d'autres SGs
#   2. monitoring_sg — ingress SSH depuis bastion_sg
#   3. app_sg — ingress SSH depuis bastion_sg + ingress 9100 depuis monitoring_sg
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "bastion" {
  name        = "chatwoot-${var.env}-bastion-sg"
  description = "SSH depuis les IPs de l'équipe — point d'entrée unique"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Egress SSH vers le subnet public (app + monitoring) — CIDR, pas de ref SG
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.public_subnet_cidrs
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-sg" })
}

resource "aws_security_group" "monitoring" {
  name        = "chatwoot-${var.env}-monitoring-sg"
  description = "Prometheus + Grafana — accès depuis bastion uniquement"
  vpc_id      = module.networking.vpc_id

  # Grafana (accès depuis bastion via tunnel SSH ou ProxyJump)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Prometheus UI
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # SSH depuis le bastion uniquement
  ingress {
    from_port       = 22
    to_port         = 22
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
  description = "Chatwoot app — HTTP public, SSH et scraping depuis bastion/monitoring"
  vpc_id      = module.networking.vpc_id

  # HTTP Chatwoot (accès public)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH depuis le bastion uniquement (plus de SSH direct depuis Internet)
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # node_exporter (port 9100) — scraping depuis l'EC2 monitoring uniquement
  ingress {
    from_port       = 9100
    to_port         = 9100
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

# ─────────────────────────────────────────────────────────────────────────────
# BASTION — Inline (staging-specific)
# Point d'entrée SSH unique. ProxyJump vers app et monitoring.
# ssh -J ubuntu@<bastion_ip> ubuntu@<app_private_ip>
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "bastion" {
  ami                         = var.bastion_ami_id
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

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-eip" })
}

# ─────────────────────────────────────────────────────────────────────────────
# EC2 APP — Inline (staging-specific)
# Chatwoot (rails + sidekiq) + PostgreSQL + Redis montés via Docker Compose.
# ACTIVE_STORAGE_SERVICE=local (pas de S3 en staging).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "app" {
  ami                    = var.app_ami_id
  instance_type          = var.app_instance_type
  key_name               = var.key_name
  subnet_id              = module.networking.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = var.iam_instance_profile_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-app" })
}

# ─────────────────────────────────────────────────────────────────────────────
# EC2 MONITORING — Inline (staging-specific)
# Prometheus (collecte métriques) + Grafana (dashboards).
# Scrape l'EC2 app via node_exporter (port 9100).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "monitoring" {
  ami                    = var.monitoring_ami_id
  instance_type          = var.monitoring_instance_type
  key_name               = var.key_name
  subnet_id              = module.networking.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = var.iam_instance_profile_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-monitoring" })
}

# ─────────────────────────────────────────────────────────────────────────────
# SSM PARAMETER STORE — Inline (staging-specific)
#
# Convention : /chatwoot/{env}/{VARIABLE_NAME}
# Type SecureString : chiffré KMS, valeurs sensibles.
# Type String : valeurs non-sensibles.
#
# lifecycle { ignore_changes = [value] } : Terraform crée le paramètre avec
# une valeur placeholder mais NE L'ÉCRASE PAS lors des applies suivants.
# Les vraies valeurs sont à renseigner manuellement ou via un script d'init.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "secret_key_base" {
  name  = "/chatwoot/${var.env}/SECRET_KEY_BASE"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "postgres_password" {
  name  = "/chatwoot/${var.env}/POSTGRES_PASSWORD"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "/chatwoot/${var.env}/REDIS_PASSWORD"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "smtp_password" {
  name  = "/chatwoot/${var.env}/SMTP_PASSWORD"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "gitlab_registry_token" {
  name  = "/chatwoot/${var.env}/GITLAB_REGISTRY_TOKEN"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "grafana_password" {
  name  = "/chatwoot/${var.env}/GRAFANA_PASSWORD"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "frontend_url" {
  name  = "/chatwoot/${var.env}/FRONTEND_URL"
  type  = "String"
  value = "http://${aws_instance.app.public_ip}"
  tags  = var.tags
}
