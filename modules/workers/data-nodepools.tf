# Copyright (c) 2022, 2023 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

data "oci_containerengine_node_pools" "current" {
  for_each = toset([for k, v in local.worker_pools_with_defaults : v.compartment_id
    if lookup(v, "mode", "") == "node-pool" && !tobool(lookup(v, "image_auto_update", true))
  ])
  compartment_id = each.value
  cluster_id     = var.cluster_id
}

locals {
  # Map of node pool name to the image it currently runs
  current_pool_image = merge([
    for _, ds in data.oci_containerengine_node_pools.current : {
      for np in ds.node_pools : np.name => try(np.node_source_details[0].image_id, null)
      if !contains(["DELETED", "DELETING"], try(np.state, ""))
    }
  ]...)
}

data "oci_containerengine_node_pools" "live_size" {
  for_each = toset([for k, v in local.worker_pools_with_defaults : v.compartment_id
    if lookup(v, "mode", "") == "node-pool" && tobool(lookup(v, "ignore_initial_pool_size", false))
  ])
  compartment_id = each.value
  cluster_id     = var.cluster_id
}

locals {
  # Map of node pool name to its current size, so pools scaled outside Terraform keep their size
  live_node_pool_size = merge([
    for _, ds in data.oci_containerengine_node_pools.live_size : {
      for np in ds.node_pools : np.name => np.node_config_details[0].size
      if !contains(["DELETED", "DELETING"], try(np.state, "")) && try(np.node_config_details[0].size, null) != null
    }
  ]...)
}
