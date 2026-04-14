data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  sorted_hashicups = sort(tolist(var.hashicups_services))

  user_data_docker = <<-EOT
    #!/bin/bash
    set -euo pipefail
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user || true
  EOT

  # Optional: standard DNS port bridge to Consul (8600). See vm/consul/dnsmasq-bridge/README.md
  user_data_dnsmasq_bridge = var.enable_consul_dns_bridge ? join("\n", [
    "",
    "dnf install -y dnsmasq",
    "cat >/etc/dnsmasq.d/10-consul-bridge.conf <<'CFG'",
    "bind-interfaces",
    "listen-address=0.0.0.0",
    "no-resolv",
    "cache-size=0",
    "server=/consul/127.0.0.1#8600",
    "CFG",
    "systemctl enable dnsmasq",
    "systemctl restart dnsmasq",
  ]) : ""

  user_data_consul_server = "${local.user_data_docker}${local.user_data_dnsmasq_bridge}"
}

resource "aws_security_group" "vm_dc" {
  name        = "${var.project_name}-vm-dc"
  description = "Consul VM datacenter and HashiCups - intra-cluster + SSH from VPC"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # Kubernetes / other VPC hosts must reach Consul and mesh gateway on the server VM.
  ingress {
    description = "Consul server RPC, HTTP, gRPC, DNS (TCP) from VPC"
    from_port   = 8300
    to_port     = 8600
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "Consul DNS and serf (UDP) from VPC"
    from_port   = 8301
    to_port     = 8600
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "Connect mesh gateway (Envoy) from VPC peers e.g. kind NodePort path"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "dnsmasq Consul DNS bridge (standard port 53 to 8600 on consul-server when enable_consul_dns_bridge)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "dnsmasq Consul DNS bridge TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "All TCP between instances in this SG (Docker published app ports)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "UDP between instances in this SG"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vm-dc-sg"
  }
}

resource "aws_instance" "consul_server" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.consul_server_instance_type
  subnet_id                   = var.subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.vm_dc.id]
  associate_public_ip_address = var.enable_public_ip
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null
  user_data                   = local.user_data_consul_server

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-consul-server"
    Role = "consul-server"
  }
}

resource "aws_instance" "hashicups" {
  for_each                    = var.hashicups_services
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.hashicups_instance_type
  subnet_id                   = var.subnet_ids[index(local.sorted_hashicups, each.key) % length(var.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.vm_dc.id]
  associate_public_ip_address = var.enable_public_ip
  key_name                    = var.ssh_key_name != "" ? var.ssh_key_name : null
  user_data                   = local.user_data_docker

  root_block_device {
    volume_size = var.root_volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.project_name}-hc-${each.key}"
    Role = each.key
  }
}
