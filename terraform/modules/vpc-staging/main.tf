# Module VPC Staging
# VPC distinct du VPC Production (CIDR 10.1.0.0/16 vs 10.0.0.0/16)
# Même région eu-west-3, 2 AZs, single_nat_gateway=true pour réduire les coûts.

module "networking" {
  source = "../networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = true
  single_nat_gateway   = true
  tags                 = var.tags
}
