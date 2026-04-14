variable "aws_region" {
  type        = string
  description = "AWS region."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names."
  default     = "consul-mesh-demo"
}

variable "vpc_id" {
  type        = string
  description = "VPC where VM datacenter lives (use terraform/aws output vpc_id)."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Public or private subnets for EC2 (use terraform/aws output public_subnet_ids)."
}

variable "ssh_key_name" {
  type        = string
  description = "EC2 key pair name for SSH (empty string to omit; use SSM if you attach an instance profile separately)."
  default     = ""
}

variable "consul_server_instance_type" {
  type        = string
  description = "Instance type for the single Consul server (control plane) VM."
  default     = "t3.small"
}

variable "hashicups_instance_type" {
  type        = string
  description = "Smallest instance type per HashiCups microservice VM."
  default     = "t3.micro"
}

variable "hashicups_services" {
  type        = set(string)
  description = "One EC2 instance per name (each gets its own private IP for the demo)."
  default = [
    "postgres",
    "product-api",
    "payments",
    "public-api",
    "frontend",
  ]
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root disk size for all instances (Consul + Docker images)."
  default     = 30
}

variable "enable_public_ip" {
  type        = bool
  description = "Associate public IPs (typical for public subnets + internet install)."
  default     = true
}

variable "route53_public_zone_name" {
  type        = string
  description = "Existing public Route53 zone (split-horizon private zone must exist from terraform/aws). Creates dc-vm and role A records; public records only if enable_public_ip."
  default     = ""
}

variable "enable_consul_dns_bridge" {
  type        = bool
  description = "On the Consul server VM: install dnsmasq on :53 forwarding *.consul to local Consul DNS :8600 (in-VPC dig @dc-vm ... -p 53)."
  default     = true
}

variable "consul_enterprise_license_path" {
  type        = string
  description = "Absolute path on the workstation running Terraform to your consul.hclic. Validated with fileexists() at plan; not read into Terraform state or uploaded to AWS. Copy to the server VM yourself (e.g. scp to /etc/consul.d/license.hclic). For Kubernetes use scripts/k8s-consul-license-secret.sh."
  default     = ""
  sensitive   = true
}
