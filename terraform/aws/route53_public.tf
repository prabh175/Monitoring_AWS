# Looks up an existing public hosted zone and creates per-kind-host names:
#   dc1.<zone>, dc2.<zone>, ... → aws_instance.node[*].public_ip (internet / off-VPC)
# Split-horizon: same FQDNs in a private zone associated with this VPC → node private IPs
# (in-VPC clients use private paths; see docs/DNS-ROUTE53-CONSUL.md).

data "aws_route53_zone" "public" {
  count        = var.route53_public_zone_name != "" ? 1 : 0
  name         = var.route53_public_zone_name
  private_zone = false
}

resource "aws_route53_zone" "split_horizon_private" {
  count = var.route53_public_zone_name != "" ? 1 : 0
  name  = var.route53_public_zone_name

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name        = "${var.project_name}-split-horizon"
    Purpose     = "VPC-private answers for same apex as public zone"
    Description = "See docs/DNS-ROUTE53-CONSUL.md"
  }
}

resource "aws_route53_record" "kind_cluster_public" {
  count   = var.route53_public_zone_name != "" ? var.node_count : 0
  zone_id = data.aws_route53_zone.public[0].zone_id
  name    = "dc${count.index + 1}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.node[count.index].public_ip]
}

resource "aws_route53_record" "kind_cluster_private" {
  count   = var.route53_public_zone_name != "" ? var.node_count : 0
  zone_id = aws_route53_zone.split_horizon_private[0].zone_id
  name    = "dc${count.index + 1}"
  type    = "A"
  ttl     = 300
  records = [aws_instance.node[count.index].private_ip]
}
