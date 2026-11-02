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
