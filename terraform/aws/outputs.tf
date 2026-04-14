output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "node_public_ips" {
  value = aws_instance.node[*].public_ip
}

output "node_private_ips" {
  value = aws_instance.node[*].private_ip
}

output "bastion_public_ip" {
  description = "SSH: ssh -i KEY ec2-user@<this> (then jump to private IPs inside the VPC)."
  value       = try(aws_instance.bastion[0].public_ip, null)
}

output "bastion_private_ip" {
  value = try(aws_instance.bastion[0].private_ip, null)
}

output "private_zone_id" {
  value = try(aws_route53_zone.private[0].zone_id, null)
}

output "route53_public_zone_id" {
  description = "Hosted zone id when route53_public_zone_name is set."
  value       = try(data.aws_route53_zone.public[0].zone_id, null)
}

output "cluster_dns_names" {
  description = "FQDNs for kind hosts (dc1, dc2, ...) when route53_public_zone_name is set."
  value       = var.route53_public_zone_name != "" ? [for i in range(var.node_count) : "dc${i + 1}.${var.route53_public_zone_name}"] : []
}

output "split_horizon_private_zone_id" {
  description = "Private hosted zone id (same apex as public); in-VPC lookups prefer these A records."
  value       = try(aws_route53_zone.split_horizon_private[0].zone_id, null)
}
