output "vpc_id" {
  description = "VPC ID — paste into terraform/eks/terraform.tfvars."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "3 public subnet IDs (one per AZ) — paste into terraform/eks/terraform.tfvars."
  value       = aws_subnet.public[*].id
}

output "bastion_public_ip" {
  description = "Bastion public IP (null when enable_bastion = false). SSH: ssh -i KEY ec2-user@<this>."
  value       = try(aws_instance.bastion[0].public_ip, null)
}

output "bastion_private_ip" {
  value = try(aws_instance.bastion[0].private_ip, null)
}

output "private_zone_id" {
  value = try(aws_route53_zone.private[0].zone_id, null)
}

output "route53_public_zone_id" {
  description = "Hosted zone ID when route53_public_zone_name is set."
  value       = try(data.aws_route53_zone.public[0].zone_id, null)
}

output "split_horizon_private_zone_id" {
  description = "Private hosted zone ID (same apex as public zone; in-VPC lookups use this)."
  value       = try(aws_route53_zone.split_horizon_private[0].zone_id, null)
}
