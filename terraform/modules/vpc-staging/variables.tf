variable "env" {
  description = "Nom de l'environnement"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC staging"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Liste des CIDR des subnets publics"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Liste des CIDR des subnets privés"
  type        = list(string)
}

variable "availability_zones" {
  description = "Liste des AZs utilisées"
  type        = list(string)
}

variable "tags" {
  description = "Tags communs appliqués à toutes les ressources"
  type        = map(string)
  default     = {}
}
