# Optional: split-horizon DNS (see docs/DNS-ROUTE53-CONSUL.md).
#   Public zone: dc-vm, <role> → instance public IPs (when enable_public_ip).
#   Private zone (same apex, created by terraform/aws): same names → private IPs for in-VPC use.

locals {
  route53_private_enabled = var.route53_public_zone_name != ""
  route53_public_enabled  = var.route53_public_zone_name != "" && var.enable_public_ip
}

data "aws_route53_zone" "public" {
  count        = local.route53_public_enabled ? 1 : 0
  name         = var.route53_public_zone_name
  private_zone = false
}

data "aws_route53_zone" "split_private" {
  count        = local.route53_private_enabled ? 1 : 0
  name         = var.route53_public_zone_name
  private_zone = true
  vpc_id       = var.vpc_id
}

resource "aws_route53_record" "dc_vm_public" {
  count   = local.route53_public_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.public[0].zone_id
  name    = "dc-vm"
  type    = "A"
  ttl     = 300
  records = [aws_instance.consul_server.public_ip]
}

resource "aws_route53_record" "dc_vm_private" {
  count   = local.route53_private_enabled ? 1 : 0
  zone_id = data.aws_route53_zone.split_private[0].zone_id
  name    = "dc-vm"
  type    = "A"
  ttl     = 300
  records = [aws_instance.consul_server.private_ip]
}

resource "aws_route53_record" "hashicups_service_public" {
  for_each = local.route53_public_enabled ? var.hashicups_services : toset([])
  zone_id  = data.aws_route53_zone.public[0].zone_id
  name     = each.key
  type     = "A"
  ttl      = 300
  records  = [aws_instance.hashicups[each.key].public_ip]
}

resource "aws_route53_record" "hashicups_service_private" {
  for_each = local.route53_private_enabled ? var.hashicups_services : toset([])
  zone_id  = data.aws_route53_zone.split_private[0].zone_id
  name     = each.key
  type     = "A"
  ttl      = 300
  records  = [aws_instance.hashicups[each.key].private_ip]
}
