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
# SHARED MODULE — Networking
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Users (Terraform/CI) + EC2 Role + Instance Profile
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS — Inline (staging-specific)
#
# Creation order (no circular dependency):
#   1. bastion_sg  — no reference to other SGs
#   2. monitoring_sg — ingress SSH depuis bastion_sg
#   3. app_sg — ingress SSH depuis bastion_sg + ingress 9100 depuis monitoring_sg
# ─────────────────────────────────────────────────────────────────────────────

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

  # Egress SSH to app and monitoring (for ProxyJump and tunnels SSH)
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
  description = "Prometheus + Grafana — accessible from bastion only"
  vpc_id      = module.networking.vpc_id

  # Grafana (access from bastion via SSH tunnel or ProxyJump)
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

  # SSH from bastion only
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
  description = "Chatwoot app — public HTTP, SSH and scraping from bastion/monitoring"
  vpc_id      = module.networking.vpc_id

  # HTTP Chatwoot (public access)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH only from bastion (ProxyJump, tunnels SSH)
  ingress {
    from_port       = 2022
    to_port         = 2022
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # node_exporter (port 9100) — from monitoring ec2 only
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
# Single SSH entry point. ProxyJump to app and monitoring.
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
# Chatwoot (rails + sidekiq) + PostgreSQL + Redis running via Docker Compose.
# ACTIVE_STORAGE_SERVICE=local (no S3 in staging).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "app" {
  ami                    = var.app_ami_id
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

  user_data = base64encode(file("${path.module}/../../../docker/scripts/chatwoot-start.sh"))

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-app", Role = "chatwoot" })
}

# ─────────────────────────────────────────────────────────────────────────────
# EC2 MONITORING — Inline (staging-specific)
# Prometheus (metrics collection) + Grafana (dashboards).
# Scrapes the app EC2 via node_exporter (port 9100).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "monitoring" {
  ami                    = var.monitoring_ami_id
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

  user_data = base64encode(file("${path.module}/../../../docker/scripts/monitoring-start.sh"))

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-monitoring" })
}

# ─────────────────────────────────────────────────────────────────────────────
# SSM PARAMETER STORE — Inline (staging-specific)
#
# Convention: /chatwoot/{env}/{VARIABLE_NAME}
# Type SecureString: KMS-encrypted, sensitive values.
# Type String: non-sensitive values.
#
# lifecycle { ignore_changes = [value] }: Terraform creates the parameter with
# a placeholder value but does NOT overwrite it on subsequent applies.
# Actual values must be set manually or via an init script.
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

# Tag de l'image Docker à déployer — mis à jour par la CI après chaque build.
# Terraform crée le paramètre avec "latest" mais ne l'écrase jamais ensuite.
# Rollback : aws ssm put-parameter --name /chatwoot/{env}/DOCKER_IMAGE_TAG --value <tag> --overwrite
resource "aws_ssm_parameter" "docker_image_tag" {
  name  = "/chatwoot/${var.env}/DOCKER_IMAGE_TAG"
  type  = "String"
  value = "latest"
  lifecycle { ignore_changes = [value] }
  tags = var.tags
}

resource "aws_ssm_parameter" "frontend_url" {
  name  = "/chatwoot/${var.env}/FRONTEND_URL"
  type  = "String"
  value = "http://${aws_instance.app.public_ip}"
  tags  = var.tags
}

# Staging : postgres et redis tournent en local dans Docker Compose
resource "aws_ssm_parameter" "postgres_host" {
  name  = "/chatwoot/${var.env}/POSTGRES_HOST"
  type  = "String"
  value = "postgres"
  tags  = var.tags
}

resource "aws_ssm_parameter" "redis_url" {
  name  = "/chatwoot/${var.env}/REDIS_URL"
  type  = "String"
  value = "redis://redis:6379"
  tags  = var.tags
}
