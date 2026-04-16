variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names and tags."
  default     = "consul-mesh-demo"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 CIDR. Must be large enough for 3 public subnets (/4 split = /20 each)."
  default     = "10.0.0.0/16"
}

variable "private_zone_domain" {
  type        = string
  description = "Private Route53 zone linked to this VPC. Do not reuse the public zone name here."
  default     = ""
}

variable "route53_public_zone_name" {
  type        = string
  description = "Existing public Route53 hosted zone in this account (optional). When set, creates A records for EKS services."
  default     = ""
}

# ── Bastion (optional — not needed for EKS) ────────────────────────────────────

variable "enable_bastion" {
  type        = bool
  description = "Provision a bastion for SSH into the VPC. Not needed for EKS; enable only if adding the VM datacenter."
  default     = false
}

variable "bastion_ssh_cidr_blocks" {
  type        = list(string)
  description = "Your laptop public IP as [\"x.x.x.x/32\"]. Required when enable_bastion is true."
  default     = []
}

variable "bastion_instance_type" {
  type        = string
  description = "Bastion EC2 size."
  default     = "t3.micro"
}

variable "ssh_key_name" {
  type        = string
  description = "EC2 key pair name. Required when enable_bastion is true."
  default     = ""
}
