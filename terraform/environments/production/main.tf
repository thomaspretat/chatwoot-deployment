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
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # SSH egress to private subnets (EC2 ASG) — no reference to ec2_sg
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-sg" })
}

resource "aws_security_group" "ec2" {
  name        = "chatwoot-${var.env}-ec2-sg"
  description = "Accessible only from ALB (port 3000) and Bastion (port 22)"
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
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
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
  identifier            = "chatwoot-${var.env}"
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
  backup_retention_period = 7
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
# ROUTE53 — Hosted zone + enregistrement A vers l'ALB
#
# Step 1: terraform apply → creates the zone and ACM validation records
# Step 2: terraform output route53_nameservers → copy the 4 NS records
# Step 3: enter the NS records at your registrar (OVH, Gandi, Namecheap...)
# Step 4: wait for ACM validation (~5 min after DNS propagation)
# Step 5: uncomment the HTTPS listener below + terraform apply
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_route53_zone" "this" {
  name = var.domain_name
  tags = merge(var.tags, { Name = var.domain_name })
}

resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ACM — TLS Certificate
# Terraform creates the certificate and DNS validation records in Route53.
# ACM validates automatically once NS records are propagated at the registrar.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_acm_certificate" "this" {
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
  tags = merge(var.tags, { Name = var.domain_name })
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
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
#   certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
#
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.this.arn
#   }
# }

# ─────────────────────────────────────────────────────────────────────────────
# BASTIONS — 2 instances (1 par AZ) with Elastic IP
# ProxyJump : ssh -J ubuntu@<bastion_ip> ubuntu@<ec2_private_ip>
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "bastion" {
  count                       = 2
  ami                         = var.bastion_ami_id
  instance_type               = var.bastion_instance_type
  key_name                    = var.key_name
  subnet_id                   = module.networking.public_subnet_ids[count.index]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-${count.index + 1}" })
}

resource "aws_eip" "bastion" {
  count    = 2
  instance = aws_instance.bastion[count.index].id
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "chatwoot-${var.env}-bastion-eip-${count.index + 1}" })
}

# ─────────────────────────────────────────────────────────────────────────────
# ASG — Launch Template + Auto Scaling Group + scaling policies
# Rolling update via Instance Refresh (min_healthy_percentage=50).
# IMPORTANT: db:chatwoot_prepare is run by the CI pipeline via SSM,
#            NOT in user-data (avoids migration conflicts on scale-out).
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_launch_template" "this" {
  name_prefix   = "chatwoot-${var.env}-"
  image_id      = var.app_ami_id
  instance_type = var.app_instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = var.iam_instance_profile_name
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

  user_data = filebase64("${path.root}/../../scripts/userdata-production.sh")

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "chatwoot-${var.env}-app" })
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
      min_healthy_percentage = 50
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

# Values automatically computed by Terraform (AWS endpoints)
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
