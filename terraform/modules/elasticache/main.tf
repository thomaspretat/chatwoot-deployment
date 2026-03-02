resource "aws_elasticache_subnet_group" "this" {
  name       = "chatwoot-${var.env}-redis-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "chatwoot-${var.env}-redis-subnet-group" })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "chatwoot-${var.env}-redis"
  description          = "Chatwoot Redis - ${var.env}"

  node_type          = var.node_type
  num_cache_clusters = var.num_cache_clusters
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]

  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled

  engine_version = "7.0"

  maintenance_window       = "sun:05:00-sun:06:00"
  snapshot_retention_limit = var.env == "production" ? 5 : 1
  snapshot_window          = "04:00-05:00"

  tags = merge(var.tags, { Name = "chatwoot-${var.env}-redis" })
}
