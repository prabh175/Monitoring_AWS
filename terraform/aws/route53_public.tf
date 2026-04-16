# Public hosted zone lookup and split-horizon private zone.
# A records for dc1/dc2 are NOT created here — EKS mesh gateway and UI NLB hostnames
# are only known after Consul is installed via Helm. Add CNAME/alias records at that
# point, or use the ELB DNS names directly during the demo.
# See docs/DNS-ROUTE53-CONSUL.md for split-horizon details.

data "aws_route53_zone" "public" {
  count        = var.route53_public_zone_name != "" ? 1 : 0
  name         = var.route53_public_zone_name
  private_zone = false
}

# Split-horizon: same apex as the public zone, associated with this VPC.
# In-VPC DNS queries resolve to private addresses; external queries use the public zone.
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

# Add CNAME records here once EKS LoadBalancer hostnames are known, for example:
#
# resource "aws_route53_record" "mesh_gw_dc1" {
#   zone_id = data.aws_route53_zone.public[0].zone_id
#   name    = "mesh-gw-dc1"
#   type    = "CNAME"
#   ttl     = 60
#   records = ["<consul-dc1-mesh-gateway-nlb-hostname>"]
# }
