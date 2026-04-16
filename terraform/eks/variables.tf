variable "aws_region" {
  type        = string
  description = "AWS region. Must match the region used for terraform/aws."
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID. Get from: cd terraform/aws && terraform output -raw vpc_id"
}

variable "subnet_ids" {
  type        = list(string)
  description = "At least 3 public subnet IDs (one per AZ) so EKS can distribute nodes. Get from: terraform output -json public_subnet_ids"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version. Check https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html for supported versions."
  default     = "1.31"
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for EKS worker nodes. m5.xlarge (16 GiB, 4 vCPU) x 3 nodes = 48 GiB per cluster, enough for 3 Consul servers, mesh gateway, HashiCups, and monitoring."
  default     = "m5.xlarge"
}

variable "node_count" {
  type        = number
  description = "Worker nodes per EKS cluster. 3 places one Consul server pod per AZ for HA."
  default     = 3
}

variable "project_name" {
  type        = string
  description = "Tag prefix used on resources. Must match the value used in terraform/aws."
  default     = "consul-mesh-demo"
}

variable "developer_iam_role_arn" {
  type        = string
  description = <<-EOT
    IAM role ARN to grant cluster-admin access (kubectl from your laptop).
    Use the ROLE ARN, not the session ARN — strip the session suffix:
      assumed-role ARN:  arn:aws:sts::123456:assumed-role/MyRole/session-name
      role ARN to use:   arn:aws:iam::123456:role/MyRole
    Get it with: aws sts get-caller-identity --query Arn --output text
  EOT
  default     = ""
}
