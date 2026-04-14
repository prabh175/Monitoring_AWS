output "consul_server_instance_id" {
  value = aws_instance.consul_server.id
}

output "consul_server_private_ip" {
  value = aws_instance.consul_server.private_ip
}

output "consul_server_public_ip" {
  value = aws_instance.consul_server.public_ip
}

output "hashicups_private_ips" {
  value = { for k, inst in aws_instance.hashicups : k => inst.private_ip }
}

output "hashicups_public_ips" {
  value = { for k, inst in aws_instance.hashicups : k => inst.public_ip }
}

output "security_group_id" {
  value = aws_security_group.vm_dc.id
}

output "consul_retry_join_hint" {
  description = "Use when templating vm/consul/client.hcl (retry_join to this IP)."
  value       = "export CONSUL_SERVER_IP=${aws_instance.consul_server.private_ip}"
}

output "dc_vm_dns_name" {
  description = "FQDN for Consul server VM when route53_public_zone_name is set (split-horizon: private IP in-VPC)."
  value       = var.route53_public_zone_name != "" ? "dc-vm.${var.route53_public_zone_name}" : null
}

output "hashicups_dns_names" {
  description = "FQDN per HashiCups role when route53_public_zone_name is set."
  value = var.route53_public_zone_name != "" ? {
    for k, _ in aws_instance.hashicups : k => "${k}.${var.route53_public_zone_name}"
  } : {}
}

output "consul_dns_bridge_hint" {
  description = "When enable_consul_dns_bridge is true, query Consul catalog DNS on port 53 via the dc-vm hostname or IP."
  value       = var.enable_consul_dns_bridge && var.route53_public_zone_name != "" ? "dig @dc-vm.${var.route53_public_zone_name} -p 53 frontend.service.consul" : null
}

output "prepared_query_http_example" {
  description = "Example prepared-query execute URL (replace query name; ACL token if required)."
  value       = var.route53_public_zone_name != "" ? "http://dc-vm.${var.route53_public_zone_name}:8500/v1/query/<query-name>/execute?near=_geo" : null
}

output "consul_enterprise_license_path_set" {
  description = "True when consul_enterprise_license_path was non-empty at apply (file must exist at plan time)."
  value       = var.consul_enterprise_license_path != ""
}
