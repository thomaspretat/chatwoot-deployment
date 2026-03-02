output "vpc_id" {
  description = "ID du VPC production"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "Bloc CIDR du VPC production"
  value       = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs des subnets publics (1 par AZ)"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs des subnets privés (1 par AZ)"
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs des NAT Gateways (1 par AZ)"
  value       = module.networking.nat_gateway_ids
}
