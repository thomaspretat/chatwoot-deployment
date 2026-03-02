# Module VPC Production — eu-west-3, Multi-AZ
# Réseau isolé pour la production Chatwoot.
# - DNS support + DNS hostnames activés
# - 1 Public Subnet + 1 Private Subnet par AZ (4 subnets pour 2 AZs)
# - 1 NAT Gateway par AZ (haute disponibilité, pas de dépendance inter-AZ)
# - State Terraform stocké dans S3 + verrou DynamoDB (voir backend.tf)

module "networking" {
  source = "../networking"

  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = true
  single_nat_gateway   = false
  tags                 = var.tags
}
