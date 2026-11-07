# Copyright (c) 2017, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

module "cluster-addons" {
  count  = local.cluster_enabled && lower(var.cluster_type) == "enhanced" ? 1 : 0
  source = "./modules/cluster-addons"

  operator_enabled = local.operator_enabled

  cluster_addons           = var.cluster_addons
  cluster_addons_to_remove = var.cluster_addons_to_remove

  cluster_id         = coalesce(var.cluster_id, one(module.cluster[*].cluster_id))
  kubernetes_version = var.kubernetes_version
  region             = var.region

  # Local execution
  kube_exec_local         = local.kube_exec_local
  kube_exec_script        = local.kube_exec_script
  kube_exec_kube_endpoint = local.kube_exec_kube_endpoint

  # Bastion/operator connection
  ssh_private_key = sensitive(local.ssh_private_key)
  bastion_host    = local.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = local.operator_private_ip
  operator_user   = var.operator_user
}


# output "supported_addons" {
#   description = "Supported cluster addons"
#   value       = var.output_detail ? try(one(module.cluster-addons[*].supported_addons), null) : null
# }