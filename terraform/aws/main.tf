# Layer 1: minimal AWS networking + instances. Extend with NLBs and records when Consul endpoints are known.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = min(3, length(data.aws_availability_zones.available.names))
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "bastion" {
  count       = var.enable_bastion ? 1 : 0
  name        = "${var.project_name}-bastion"
  description = "SSH from operator laptop to bastion only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed CIDRs (your Mac)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_ssh_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}

resource "aws_instance" "bastion" {
  count                       = var.enable_bastion ? 1 : 0
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion[0].id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  }
}

resource "aws_security_group" "nodes" {
  name        = "${var.project_name}-nodes"
  description = "Kind / Docker / SSH / mesh NodePort - tighten for production."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Mesh gateway NodePort (customer standard)"
    from_port   = 31443
    to_port     = 31443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Consul LAN (between nodes)"
    from_port   = 8301
    to_port     = 8302
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Consul LAN UDP"
    from_port   = 8301
    to_port     = 8302
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nodes"
  }
}

resource "aws_instance" "node" {
  count                       = var.node_count
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.node_instance_type
  subnet_id                   = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids      = [aws_security_group.nodes.id]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null

  root_block_device {
    volume_size = 80
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-node-${count.index + 1}"
    Role = "kind-or-consul-vm"
  }
}

resource "aws_route53_zone" "private" {
  count = var.private_zone_domain != "" ? 1 : 0
  name  = var.private_zone_domain

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = "${var.project_name}-private"
  }
}

check "bastion_inputs" {
  assert {
    condition = !var.enable_bastion || (
      length(var.bastion_ssh_cidr_blocks) > 0 && var.ssh_key_name != ""
    )
    error_message = "When enable_bastion is true, set bastion_ssh_cidr_blocks (e.g. your Mac public IP /32) and ssh_key_name in tfvars."
  }
}

# After Consul NLBs exist, add aws_route53_record resources (failover or weighted) pointing to NLB aliases.
# Example pattern (commented):
#
# resource "aws_route53_record" "dc1_ui" {
#   zone_id = aws_route53_zone.private[0].zone_id
#   name    = "dc1.${var.private_zone_domain}"
#   type    = "A"
#   alias {
#     name                   = aws_lb.dc1_consul.dns_name
#     zone_id                = aws_lb.dc1_consul.zone_id
#     evaluate_target_health = true
#   }
# }
