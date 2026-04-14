variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names."
  default     = "consul-mesh-demo"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 CIDR."
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for Kind hosts and/or Consul VM nodes."
  default     = "m6i.large"
}

variable "node_count" {
  type        = number
  description = "EC2 instances. Example: 2 = one VM per kind cluster (dc1/dc2); add more for a separate VM Consul datacenter."
  default     = 2
}

variable "private_zone_domain" {
  type        = string
  description = "Private Route53 zone linked to this VPC (internal DNS). Do not set this to your public demo zone; use route53_public_zone_name instead."
  default     = ""
}

variable "route53_public_zone_name" {
  type        = string
  description = "Existing public Route53 hosted zone name (same AWS account). When set, creates A records dc1, dc2, ... pointing at kind node public IPs."
  default     = ""
}

variable "enable_bastion" {
  type        = bool
  description = "Provision a public bastion for SSH from your laptop into the VPC (then jump to private IPs)."
  default     = true
}

variable "bastion_ssh_cidr_blocks" {
  type        = list(string)
  description = "CIDRs allowed to SSH to the bastion only (e.g. [\"203.0.113.50/32\"] for your Mac). Required when enable_bastion is true."
  default     = []
}

variable "bastion_instance_type" {
  type        = string
  description = "Bastion EC2 size."
  default     = "t3.micro"
}

variable "ssh_key_name" {
  type        = string
  description = "EC2 key pair name for bastion (and optional for other instances). Required when enable_bastion is true."
  default     = ""
}
