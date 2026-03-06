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

# ─────────────────────────────────────────────────────────────────────────────
# AMI LOOKUPS — Fetch latest Packer-built AMIs automatically
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# SHARED MODULES
# These modules are reused between prod and staging with different variables.
# ─────────────────────────────────────────────────────────────────────────────

module "networking" {
  source = "../../modules/networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = true  # 1 NAT GW per AZ (high availability)
  single_nat_gateway   = false
  tags                 = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS — Inline (production-specific)
#
# Cross-SG egress rules use CIDRs to avoid circular dependencies
# (e.g. ALB SG → EC2 SG → ALB SG). Security is maintained via strict ingress rules.
# ─────────────────────────────────────────────────────────────────────────────

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

  # Egress to private subnets on app port (avoids circular reference with ec2_sg)
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

  # SSH egress to private subnets (EC2 ASG) — no reference to ec2_sg
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

  # Application traffic from ALB only
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH from bastion only
  ingress {
    from_port       = 2022
    to_port         = 2022
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # node-exporter scraping from monitoring instance
  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  # redis-exporter scraping from monitoring instance
  ingress {
    from_port       = 9121
    to_port         = 9121
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  # Full egress: Docker image pull, Secrets Manager (HTTPS), S3, SSM
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

# ─────────────────────────────────────────────────────────────────────────────
# IAM — Users (Terraform/CI) + EC2 Role + Instance Profile
# ─────────────────────────────────────────────────────────────────────────────

module "iam" {
  source        = "../../modules/iam"
  env           = var.env
  s3_bucket_arn = aws_s3_bucket.chatwoot.arn
  tags          = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# S3 — Chatwoot storage (ACTIVE_STORAGE_SERVICE=amazon)
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# RDS PostgreSQL 16 — Multi-AZ, private subnet, encrypted
# Chatwoot v4+ requires pgvector, natively supported on RDS PG16.
# db:chatwoot_prepare enables the extension automatically on first deployment.
# ─────────────────────────────────────────────────────────────────────────────

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
  identifier            = "chatwoot_production"
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
  backup_retention_period = 14
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection               = true
  skip_final_snapshot               = false
  final_snapshot_identifier         = "chatwoot-${var.env}-final"
  performance_insights_enabled      = true

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-rds" })
}

# ─────────────────────────────────────────────────────────────────────────────
# ELASTICACHE REDIS 7 — Multi-AZ, TLS enabled (transit_encryption_enabled=true)
# Use REDIS_URL=rediss:// (double s) + REDIS_OPENSSL_VERIFY_MODE=none
# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────
# ACM — TLS Certificate (validated manually via Cloudflare DNS)
#
# Step 1: terraform apply → creates the certificate in "Pending validation"
# Step 2: terraform output acm_validation_record → copy the CNAME into Cloudflare
# Step 3: wait for ACM validation (~5 min after DNS propagation)
# Step 4: uncomment the HTTPS listener below + terraform apply
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = merge(var.tags, { Name = var.domain_name })
}

# ─────────────────────────────────────────────────────────────────────────────
# ALB — Application Load Balancer, multi-AZ, public subnets
# Listener 80 → redirect 443
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "this" {
  name                       = "chatwoot-${var.env}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.networking.public_subnet_ids
  enable_deletion_protection = true
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

# resource "aws_lb_listener" "https" {
#   load_balancer_arn = aws_lb.this.arn
#   port              = 443
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
#   certificate_arn   = aws_acm_certificate.this.arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.this.arn
#   }
# }

# ─────────────────────────────────────────────────────────────────────────────
# BASTION — Single SSH entry point (can reach both AZs within the VPC)
# ProxyJump : ssh -J ubuntu@<bastion_ip> ubuntu@<ec2_private_ip>
# ─────────────────────────────────────────────────────────────────────────────

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

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-eip" })
}

# ─────────────────────────────────────────────────────────────────────────────
# ASG — Launch Template + Auto Scaling Group + scaling policies
# Rolling update via Instance Refresh (min_healthy_percentage=100).
# 100% = new instance must be healthy before old one is terminated (one at a time).
# db:chatwoot_prepare runs at boot on every instance.
# ─────────────────────────────────────────────────────────────────────────────

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
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "chatwoot-${var.env}-app", Role = "chatwoot" })
  }

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
  health_check_type         = "ELB"
  health_check_grace_period = 120

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

# ─────────────────────────────────────────────────────────────────────────────
# MONITORING — Single instance in AZ-a (outside ASG)
# Prometheus (metrics collection) + Grafana (dashboards).
# Scrapes app instances via node_exporter (port 9100) and redis_exporter (port 9121).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "monitoring" {
  name        = "chatwoot-${var.env}-monitoring-sg"
  description = "Prometheus + Grafana — accessible from Bastion (SSH) and scrapes EC2"
  vpc_id      = module.networking.vpc_id

  # Grafana (from allowed_ssh_cidrs for dashboard access)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Prometheus (from allowed_ssh_cidrs for direct access)
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

  # Full egress: Docker pulls, SSM, scraping app instances
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

# ─────────────────────────────────────────────────────────────────────────────
# SSM PARAMETER STORE — Inline (production-specific)
#
# Convention: /chatwoot/{env}/{VARIABLE_NAME}
# Type SecureString: KMS-encrypted, sensitive values.
# Type String: non-sensitive values (endpoints computed by Terraform).
#
# lifecycle { ignore_changes = [value] }: Terraform creates the parameter with
# a placeholder value but does NOT overwrite it on subsequent applies.
# Actual values must be set manually or via the CI pipeline.
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

# Valeurs calculées automatiquement par Terraform (endpoints AWS)
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

# REDIS_ADDR est utilisé par le redis-exporter (oliver006/redis_exporter).
# Même endpoint que REDIS_URL mais sans le suffixe /0 (numéro de DB Redis),
# car le redis-exporter ne supporte pas ce format.
# Doc : https://github.com/oliver006/redis_exporter
resource "aws_ssm_parameter" "redis_addr" {
  name  = "/chatwoot/${var.env}/REDIS_ADDR"
  type  = "String"
  value = "rediss://${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
  tags  = var.tags
}

resource "aws_ssm_parameter" "frontend_url" {
  name  = "/chatwoot/${var.env}/FRONTEND_URL"
  type  = "String"
  value = "https://${var.domain_name}"
  tags  = var.tags
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/chatwoot/${var.env}/S3_BUCKET_NAME"
  type  = "String"
  value = aws_s3_bucket.chatwoot.bucket
  tags  = var.tags
}

resource "aws_ssm_parameter" "active_storage_service" {
  name  = "/chatwoot/${var.env}/ACTIVE_STORAGE_SERVICE"
  type  = "String"
  value = "amazon"
  tags  = var.tags
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "/chatwoot/${var.env}/AWS_REGION"
  type  = "String"
  value = var.aws_region
  tags  = var.tags
}

resource "aws_ssm_parameter" "redis_openssl_verify_mode" {
  name  = "/chatwoot/${var.env}/REDIS_OPENSSL_VERIFY_MODE"
  type  = "String"
  value = "none"
  tags  = var.tags
}
