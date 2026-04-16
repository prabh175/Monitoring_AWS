output "clusters" {
  description = "EKS cluster details. Run kubeconfig_cmd for each cluster to configure kubectl on your laptop."
  value = {
    for k, m in module.eks : k => {
      cluster_name     = m.cluster_name
      cluster_endpoint = m.cluster_endpoint
      kubeconfig_cmd   = "aws eks update-kubeconfig --region ${var.aws_region} --name ${m.cluster_name} --alias ${k}"
    }
  }
}

output "node_security_group_ids" {
  description = "Node security group IDs per cluster. Mesh gateway ingress rules reference these."
  value       = { for k, m in module.eks : k => m.node_security_group_id }
}

output "cluster_certificate_authorities" {
  description = "Base64-encoded cluster CA certificates (used in kubeconfig)."
  sensitive   = true
  value       = { for k, m in module.eks : k => m.cluster_certificate_authority_data }
}
