variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

# Networking
variable "vpc_cidr" {
  description = "CIDR block for the staging VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (1 only in staging)"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones (1 only in staging)"
  type        = list(string)
}

# Accès SSH
variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH and to access Grafana/Prometheus"
  type        = list(string)
}

# EC2 Bastion
variable "bastion_instance_type" {
  description = "Instance type for the bastion EC2"
  type        = string
  default     = "t3.micro"
}

# EC2 App (Chatwoot + postgres + redis Docker)
variable "app_instance_type" {
  description = "Instance type for the app EC2"
  type        = string
  default     = "t3.small"
}

# EC2 Monitoring (Prometheus + Grafana)
variable "monitoring_instance_type" {
  description = "Instance type for the monitoring EC2"
  type        = string
  default     = "t3.micro"
}

# SSH Key 
variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

# Secrets (SSM Parameter Store)
variable "secret_key_base" {
  description = "Rails secret key base"
  type        = string
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "redis_password" {
  description = "Redis password"
  type        = string
  sensitive   = true
}

variable "smtp_password" {
  description = "SMTP password"
  type        = string
  sensitive   = true
}

variable "gitlab_registry_token" {
  description = "GitLab registry token"
  type        = string
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
}

variable "frontend_url" {
  description = "Chatwoot frontend URL (Cloudflare domain)"
  type        = string
}

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

# Tags
variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
