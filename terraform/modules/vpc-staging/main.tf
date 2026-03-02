# Module VPC Staging — Architecture simplifiée 1 AZ
# Réutilise le module networking avec single_nat_gateway = true
# et force une seule AZ pour réduire les coûts en pré-production.

module "networking" {
  source = "../networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = [var.public_subnet_cidr]
  private_subnet_cidrs = [var.private_subnet_cidr]
  availability_zones   = [var.availability_zone]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  tags                 = var.tags
}
