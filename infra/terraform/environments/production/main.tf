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
    key            = "environments/production/terraform.tfstate"
    region         = "eu-west-3"
    dynamodb_table = "chatwoot-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
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
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = true # 1 NAT GW par AZ (haute disponibilité)
  single_nat_gateway   = false
  tags                 = var.tags
}

# GROUPES DE SÉCURITÉ
# Les règles d'egress inter-SG utilisent des CIDRs pour éviter les dépendances circulaires
# (ex. ALB SG → EC2 SG → ALB SG)
resource "aws_security_group" "alb" {
  name        = "chatwoot-${var.env}-alb-sg"
  description = "Accept HTTPS/HTTP from Internet, forward to EC2 on port 3000"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress vers les sous-réseaux privés sur le port applicatif (évite la référence circulaire avec ec2_sg)
  egress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-alb-sg" })
}

resource "aws_security_group" "bastion" {
  name        = "chatwoot-${var.env}-bastion-sg"
  description = "SSH from team IPs only"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port   = 2022
    to_port     = 2022
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Egress SSH vers les sous-réseaux privés (EC2 ASG) — sans référence à ec2_sg
  egress {
    from_port   = 2022
    to_port     = 2022
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-sg" })
}

resource "aws_security_group" "ec2" {
  name        = "chatwoot-${var.env}-ec2-sg"
  description = "Accessible only from ALB (port 3000) and Bastion (port 2022)"
  vpc_id      = module.networking.vpc_id

  # Trafic applicatif depuis l'ALB uniquement
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH depuis le bastion uniquement
  ingress {
    from_port       = 2022
    to_port         = 2022
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Scraping node-exporter depuis l'instance de monitoring
  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  # Scraping redis-exporter depuis l'instance de monitoring
  ingress {
    from_port       = 9121
    to_port         = 9121
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  # Egress total : pull d'images Docker, Secrets Manager (HTTPS), S3, SSM
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-ec2-sg" })
}

resource "aws_security_group" "rds" {
  name        = "chatwoot-${var.env}-rds-sg"
  description = "PostgreSQL accessible only from EC2"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-rds-sg" })
}

resource "aws_security_group" "redis" {
  name        = "chatwoot-${var.env}-redis-sg"
  description = "Redis accessible only from EC2"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-redis-sg" })
}

# IAM — Utilisateurs (Terraform/CI) + Rôle EC2 + Profil d'instance
module "iam" {
  source           = "../../modules/iam"
  env              = var.env
  enable_s3_policy = true
  s3_bucket_arn    = aws_s3_bucket.chatwoot.arn
  tags             = var.tags
}

# S3 — Stockage Chatwoot (ACTIVE_STORAGE_SERVICE=amazon)
resource "aws_s3_bucket" "chatwoot" {
  bucket = var.s3_bucket_name
  tags   = merge(var.tags, { Name = var.s3_bucket_name })
}

resource "aws_s3_bucket_versioning" "chatwoot" {
  bucket = aws_s3_bucket.chatwoot.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "chatwoot" {
  bucket = aws_s3_bucket.chatwoot.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "chatwoot" {
  bucket                  = aws_s3_bucket.chatwoot.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "chatwoot" {
  bucket = aws_s3_bucket.chatwoot.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# RDS PostgreSQL 16 — Multi-AZ, sous-réseau privé, chiffré
# Chatwoot v4+ requiert pgvector, nativement supporté sur RDS PG16.
# db:chatwoot_prepare active l'extension automatiquement au premier déploiement.
resource "aws_db_subnet_group" "this" {
  name       = "chatwoot-${var.env}-db-subnet-group"
  subnet_ids = module.networking.private_subnet_ids
  tags       = merge(var.tags, { Name = "chatwoot-${var.env}-db-subnet-group" })
}

resource "aws_db_parameter_group" "this" {
  name   = "chatwoot-${var.env}-pg16"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-pg16" })
}

resource "aws_db_instance" "this" {
  identifier            = "chatwoot-production"
  engine                = "postgres"
  engine_version        = "16"
  instance_class        = var.rds_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  publicly_accessible   = false

  db_name  = "chatwoot_production"
  username = "chatwoot"
  password = var.rds_db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az                = true
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection          = false
  skip_final_snapshot          = false
  final_snapshot_identifier    = "chatwoot-${var.env}-final"
  performance_insights_enabled = true

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-rds" })
}

# ELASTICACHE REDIS 7 — Multi-AZ, TLS activé (transit_encryption_enabled=true)
# Utiliser REDIS_URL=rediss:// (double s) + REDIS_OPENSSL_VERIFY_MODE=none
resource "aws_elasticache_subnet_group" "this" {
  name       = "chatwoot-${var.env}-redis-subnet-group"
  subnet_ids = module.networking.private_subnet_ids
  tags       = merge(var.tags, { Name = "chatwoot-${var.env}-redis-subnet-group" })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "chatwoot-${var.env}-redis"
  description          = "Chatwoot Redis - ${var.env}"

  node_type          = var.redis_node_type
  num_cache_clusters = 2
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  engine_version           = "7.0"
  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_retention_limit = 5
  snapshot_window          = "04:00-05:00"

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-redis" })
}

# ACM — Certificat TLS (validé manuellement via DNS Cloudflare)
# Étape 1 : terraform apply → crée le certificat en statut "Pending validation"
# Étape 2 : terraform output acm_validation_record → copier le CNAME dans Cloudflare
# Étape 3 : attendre la validation ACM (~5 min après propagation DNS)
# Étape 4 : décommenter le listener HTTPS ci-dessous + terraform apply
resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = merge(var.tags, { Name = var.domain_name })
}

# ALB — Application Load Balancer, multi-AZ, sous-réseaux publics
# Listener 80 → redirection 443
resource "aws_lb" "this" {
  name                       = "chatwoot-${var.env}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.networking.public_subnet_ids
  enable_deletion_protection = false
  tags                       = merge(var.tags, { Name = "chatwoot-${var.env}-alb" })
}

resource "aws_lb_target_group" "this" {
  name     = "chatwoot-${var.env}-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = module.networking.vpc_id

  health_check {
    enabled             = true
    path                = "/health"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-tg" })
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.this.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# BASTION
# ProxyJump : ssh -J ubuntu@<bastion_ip> ubuntu@<ec2_ip_privée>
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.bastion.id
  instance_type               = var.bastion_instance_type
  key_name                    = var.key_name
  subnet_id                   = module.networking.public_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion" })
}

# ASG — Template de lancement + Groupe d'auto-scaling + politiques de mise à l'échelle
resource "aws_launch_template" "this" {
  name_prefix   = "chatwoot-${var.env}-"
  image_id      = data.aws_ami.chatwoot.id
  instance_type = var.app_instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = module.iam.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type           = "gp3"
      volume_size           = 50
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "chatwoot-${var.env}-app", Role = "chatwoot" })
  }

  # S'assurer que les paramètres SSM existent avant de lancer les instances pour que les db s'initialisent bien
  depends_on = [
    aws_ssm_parameter.postgres_host,
    aws_ssm_parameter.redis_url,
    aws_ssm_parameter.redis_addr,
    aws_ssm_parameter.s3_bucket_name,
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name                = "chatwoot-${var.env}-asg"
  vpc_zone_identifier = module.networking.private_subnet_ids
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 600

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      instance_warmup        = 120
    }
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "chatwoot-${var.env}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "chatwoot-${var.env}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.this.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "chatwoot-${var.env}-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 75
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "chatwoot-${var.env}-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 25
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.this.name }
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
}

# MONITORING — Instance unique en AZ-a (hors ASG)
# Prometheus + Grafana
resource "aws_security_group" "monitoring" {
  name        = "chatwoot-${var.env}-monitoring-sg"
  description = "Prometheus + Grafana - accessible from Bastion (SSH) and scrapes EC2"
  vpc_id      = module.networking.vpc_id

  # Grafana (depuis allowed_ssh_cidrs pour accès au tableau de bord)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Prometheus (depuis allowed_ssh_cidrs pour accès direct)
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

resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.monitoring.id
  instance_type          = "t3.micro"
  key_name               = var.key_name
  subnet_id              = module.networking.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = module.iam.instance_profile_name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-monitoring", Role = "monitoring" })
}

# SSM — Paramètres calculés automatiquement (endpoints infra, pas des secrets)
resource "aws_ssm_parameter" "postgres_host" {
  name  = "/chatwoot/${var.env}/POSTGRES_HOST"
  type  = "String"
  value = aws_db_instance.this.address
  tags  = var.tags
}

resource "aws_ssm_parameter" "redis_url" {
  name  = "/chatwoot/${var.env}/REDIS_URL"
  type  = "String"
  value = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379/0"
  tags  = var.tags
}

resource "aws_ssm_parameter" "redis_addr" {
  name  = "/chatwoot/${var.env}/REDIS_ADDR"
  type  = "String"
  value = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
  tags  = var.tags
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/chatwoot/${var.env}/S3_BUCKET_NAME"
  type  = "String"
  value = aws_s3_bucket.chatwoot.bucket
  tags  = var.tags
}
