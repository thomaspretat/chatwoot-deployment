variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

# ── Networking ──────────────────────────────────────────────────────────────

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

# ── Accès SSH ────────────────────────────────────────────────────────────────

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH and to access Grafana/Prometheus"
  type        = list(string)
}

# ── EC2 Bastion ──────────────────────────────────────────────────────────────

variable "bastion_ami_id" {
  description = "AMI ID for the bastion EC2"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion EC2"
  type        = string
  default     = "t3.micro"
}

# ── EC2 App (Chatwoot + postgres + redis Docker) ─────────────────────────────

variable "app_ami_id" {
  description = "AMI ID for the Chatwoot app EC2 (Docker pre-installed)"
  type        = string
}

variable "app_instance_type" {
  description = "Instance type for the app EC2"
  type        = string
  default     = "t3.small"
}

# ── EC2 Monitoring (Prometheus + Grafana) ────────────────────────────────────

variable "monitoring_ami_id" {
  description = "AMI ID for the monitoring EC2 (Docker pre-installed)"
  type        = string
}

variable "monitoring_instance_type" {
  description = "Instance type for the monitoring EC2"
  type        = string
  default     = "t3.micro"
}

# ── SSH Key ──────────────────────────────────────────────────────────────────

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

# ── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
