variable "env" {
  description = "Nom de l'environnement"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC production (ex: 10.0.0.0/16)"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Liste des CIDR des subnets publics (1 par AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Liste des CIDR des subnets privés (1 par AZ)"
  type        = list(string)
}

variable "availability_zones" {
  description = "Liste des AZs couvertes (min 2 pour la production)"
  type        = list(string)
}

variable "tags" {
  description = "Tags communs appliqués à toutes les ressources"
  type        = map(string)
  default     = {}
}
