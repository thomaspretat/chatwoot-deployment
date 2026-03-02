output "vpc_id" {
  description = "ID du VPC staging"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  description = "Bloc CIDR du VPC staging"
  value       = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  description = "ID du subnet public (liste à 1 élément)"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "ID du subnet privé (liste à 1 élément)"
  value       = module.networking.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "ID du NAT Gateway unique en staging"
  value       = module.networking.nat_gateway_ids
}
