# EKS clusters (dc1 / dc2)

Provisions two EKS clusters — **consul-dc1** and **consul-dc2** — in the VPC created by `terraform/aws`.

## What this creates

| Resource | Per cluster |
|----------|-------------|
| EKS control plane (managed) | 1 |
| Managed node group | 1 (3 × `m5.xlarge` across 3 AZs) |
| Add-ons | CoreDNS, kube-proxy, VPC CNI, EBS CSI driver |
| Security group rules | TCP 443 between dc1 ↔ dc2 nodes (mesh gateway) |

## Prerequisites

- `terraform/aws` has been applied — you need `vpc_id` and `public_subnet_ids` from its outputs.
- AWS CLI configured (`aws sts get-caller-identity` works).
- Your IAM user/role has permissions to create EKS clusters and IAM roles.

## Apply

```bash
# 1. Get VPC outputs from terraform/aws
cd terraform/aws
VPC_ID=$(terraform output -raw vpc_id)
SUBNETS=$(terraform output -json public_subnet_ids)

# 2. Create terraform.tfvars
cd ../eks
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with the VPC ID and subnet IDs printed above.

# 3. Apply (takes ~15 minutes)
terraform init
terraform apply
```

## Configure kubectl on your laptop

After apply, run the two commands printed in the `clusters` output:

```bash
terraform output -json clusters | jq -r '.[] .kubeconfig_cmd' | bash

# Verify both contexts are set:
kubectl config get-contexts
# CURRENT   NAME   CLUSTER       AUTHINFO
#           dc1    consul-dc1    ...
#           dc2    consul-dc2    ...

kubectl config use-context dc1
kubectl get nodes   # 3 Ready nodes
```

## Node sizing

| | Per node | Per cluster (3 nodes) |
|-|----------|-----------------------|
| RAM | 16 GiB | 48 GiB |
| vCPU | 4 | 12 |

This comfortably hosts: 3 Consul server pods (1 per node), 1 mesh gateway pod, HashiCups services, and the monitoring stack (Prometheus, Grafana, Loki, Promtail).

## Storage

The EBS CSI driver add-on creates a `gp2` StorageClass by default. Consul Helm values reference `gp2` for server PVCs. To use `gp3` (20% cheaper, faster):

```bash
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
# Then set server.storageClass: gp3 in Helm values.
```

## Do I need a bastion?

**No.** The EKS API endpoint is public (`cluster_endpoint_public_access = true`), so `kubectl` and `helm` work directly from your laptop. A bastion is only needed if you add the optional VM datacenter (Step 7) and need SSH access to those EC2 instances.
