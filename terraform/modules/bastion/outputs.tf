output "instance_ids" {
  description = "IDs of the bastion instances"
  value       = aws_instance.bastion[*].id
}

output "public_ips" {
  description = "Public Elastic IPs of the bastion instances"
  value       = aws_eip.bastion[*].public_ip
}
