# Two EKS clusters: consul-dc1 and consul-dc2.
# Both share one VPC. Subnet and VPC IDs come from terraform/aws outputs.
#
# After apply, configure kubectl with:
#   terraform output -json clusters | jq -r '.[] .kubeconfig_cmd' | bash

locals {
  datacenters = {
    dc1 = { name = "consul-dc1" }
    dc2 = { name = "consul-dc2" }
  }
}

module "eks" {
  for_each = local.datacenters
  source   = "terraform-aws-modules/eks/aws"
  version  = "~> 20.31"

  cluster_name    = each.value.name
  cluster_version = var.kubernetes_version

  # Public endpoint = kubectl works from your laptop without a bastion.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Grants the IAM identity running terraform apply automatic cluster-admin access.
  # Without this, only the AWS account root can access the cluster after creation.
  enable_cluster_creator_admin_permissions = true

  # Additional IAM principals that need cluster access.
  # Add your assumed-role ARN here so kubectl works from your laptop.
  # Use the role ARN (not the session ARN) — strip the session suffix after the last /.
  # e.g. arn:aws:sts::123:assumed-role/MyRole/session → arn:aws:iam::123:role/MyRole
  access_entries = var.developer_iam_role_arn != "" ? {
    developer = {
      principal_arn = var.developer_iam_role_arn

      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  } : {}

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # EKS module default only opens 9443 for webhooks.
  # Consul connect-injector serves its webhook on port 8080 (service maps 443→8080).
  # Without this rule the API server cannot reach the webhook and times out.
  node_security_group_additional_rules = {
    ingress_cluster_consul_webhook = {
      description                   = "Allow control plane to reach Consul webhook port 8080"
      protocol                      = "tcp"
      from_port                     = 8080
      to_port                       = 8080
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Managed add-ons. most_recent picks the latest version compatible with the cluster.
  cluster_addons = {
    coredns            = { most_recent = true }
    kube-proxy         = { most_recent = true }
    vpc-cni            = { most_recent = true }
    # EBS CSI driver provisions gp2/gp3 PVCs for Consul server storage.
    aws-ebs-csi-driver = { most_recent = true }
  }

  eks_managed_node_groups = {
    consul = {
      name           = "${each.value.name}-nodes"
      instance_types = [var.node_instance_type]

      # Fixed at 3 so Consul server pods distribute one-per-node (one per AZ).
      min_size     = var.node_count
      max_size     = var.node_count
      desired_size = var.node_count

      # Required for the EBS CSI driver add-on to provision PVCs.
      iam_role_additional_policies = {
        ebs_csi = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }

  tags = {
    Name    = each.value.name
    DC      = each.key
    Project = var.project_name
  }
}

# Allow TCP 443 (mesh gateway) between the two clusters' node security groups.
# Without this, cross-cluster peering traffic is blocked at the node level.
resource "aws_security_group_rule" "mesh_gateway_dc1_to_dc2" {
  description              = "mesh gateway TCP 443 dc2 to dc1"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks["dc1"].node_security_group_id
  source_security_group_id = module.eks["dc2"].node_security_group_id
}

resource "aws_security_group_rule" "mesh_gateway_dc2_to_dc1" {
  description              = "mesh gateway TCP 443 dc1 to dc2"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks["dc2"].node_security_group_id
  source_security_group_id = module.eks["dc1"].node_security_group_id
}
