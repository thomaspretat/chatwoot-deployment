resource "aws_db_subnet_group" "this" {
  name       = "chatwoot-${var.env}-db-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "chatwoot-${var.env}-db-subnet-group" })
}

resource "aws_db_parameter_group" "this" {
  name   = "chatwoot-${var.env}-pg15"
  family = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-pg15" })
}

resource "aws_db_instance" "this" {
  identifier             = "${var.identifier}-${var.env}"
  engine                 = "postgres"
  engine_version         = var.engine_version
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.env == "staging" ? true : false
  final_snapshot_identifier = var.env == "staging" ? null : "${var.identifier}-${var.env}-final"

  performance_insights_enabled = true

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-rds" })
}
