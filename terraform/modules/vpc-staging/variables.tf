variable "env" {
  description = "Nom de l'environnement"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC"
  type        = string
}

variable "public_subnet_cidr" {
  description = "Bloc CIDR du subnet public (1 seule AZ en staging)"
  type        = string
}

variable "private_subnet_cidr" {
  description = "Bloc CIDR du subnet privé (1 seule AZ en staging)"
  type        = string
}

variable "availability_zone" {
  description = "AZ unique utilisée en staging (ex: eu-west-3a)"
  type        = string
}

variable "tags" {
  description = "Tags communs appliqués à toutes les ressources"
  type        = map(string)
  default     = {}
}
