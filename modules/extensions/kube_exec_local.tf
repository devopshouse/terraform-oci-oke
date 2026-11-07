# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  # for_each keys come only from these booleans: a map filtered over sensitive values is itself sensitive.
  kube_exec_enabled = {
    argocd              = local.argocd_enabled
    cilium              = var.cilium_install
    cluster_autoscaler  = local.cluster_autoscaler_enabled
    dcgm_exporter       = var.dcgm_exporter_install
    gatekeeper          = local.gatekeeper_enabled
    karpenter           = local.karpenter_enabled
    kube_admin_binding  = true
    metrics_server      = local.metrics_server_enabled
    mpi_operator        = var.mpi_operator_install
    multus              = var.multus_install
    prometheus          = var.prometheus_install
    rdma_cni_plugin     = var.rdma_cni_plugin_install
    sriov_cni_plugin    = var.sriov_cni_plugin_install
    sriov_device_plugin = var.sriov_device_plugin_install
    whereabouts         = var.whereabouts_install
  }

  # Resources with a defined order have their own null_resource below.
  kube_exec_ordered = ["cilium", "kube_admin_binding", "prometheus"]

  # File key => extension. Paths are not usable as keys: they stay unknown until a new cluster has an OCID.
  kube_exec_file_owner = {
    "argocd"                 = "argocd"
    "cilium.crds"            = "cilium"
    "cilium.values_override" = "cilium"
    "cluster_autoscaler"     = "cluster_autoscaler"
    "dcgm_exporter.crds"     = "dcgm_exporter"
    "dcgm_exporter.manifest" = "dcgm_exporter"
    "gatekeeper"             = "gatekeeper"
    "karpenter"              = "karpenter"
    "kube_admin_binding"     = "kube_admin_binding"
    "metrics_server"         = "metrics_server"
    "mpi_operator"           = "mpi_operator"
    "multus"                 = "multus"
    "prometheus.crds"        = "prometheus"
    "prometheus.manifest"    = "prometheus"
    "rdma_cni_plugin"        = "rdma_cni_plugin"
    "sriov_cni_plugin"       = "sriov_cni_plugin"
    "sriov_device_plugin"    = "sriov_device_plugin"
    "whereabouts.ippools"    = "whereabouts"
    "whereabouts.overlap"    = "whereabouts"
    "whereabouts.manifest"   = "whereabouts"
  }

  kube_exec_file_path = {
    "argocd"                 = local.argocd_manifest_path
    "cilium.crds"            = local.cilium_helm_crds_file
    "cilium.values_override" = local.cilium_helm_values_override_file
    "cluster_autoscaler"     = local.cluster_autoscaler_manifest_path
    "dcgm_exporter.crds"     = local.dcgm_exporter_helm_crds_file
    "dcgm_exporter.manifest" = local.dcgm_exporter_helm_manifest_file
    "gatekeeper"             = local.gatekeeper_manifest_path
    "karpenter"              = local.karpenter_manifest_path
    "kube_admin_binding"     = join("/", [local.yaml_manifest_path, "kube-admin-binding.yaml"])
    "metrics_server"         = local.metrics_server_manifest_path
    "mpi_operator"           = local.mpi_operator_manifest_path
    "multus"                 = local.multus_manifest_path
    "prometheus.crds"        = local.prometheus_helm_crds_file
    "prometheus.manifest"    = local.prometheus_helm_manifest_file
    "rdma_cni_plugin"        = local.rdma_cni_plugin_manifest_path
    "sriov_cni_plugin"       = local.sriov_cni_plugin_manifest_path
    "sriov_device_plugin"    = local.sriov_device_plugin_manifest_path
    "whereabouts.ippools"    = local.whereabouts_ippools_path
    "whereabouts.overlap"    = local.whereabouts_overlap_res_path
    "whereabouts.manifest"   = local.whereabouts_manifest_path
  }

  kube_exec_file_content = {
    "argocd"                 = local.argocd_manifest
    "cilium.crds"            = try(join("\n", local.cilium_helm_crds), null)
    "cilium.values_override" = local.cilium_helm_values_override_yaml
    "cluster_autoscaler"     = local.cluster_autoscaler_manifest
    "dcgm_exporter.crds"     = try(join("\n", local.dcgm_exporter_helm_crds), null)
    "dcgm_exporter.manifest" = local.dcgm_exporter_helm_manifest
    "gatekeeper"             = local.gatekeeper_manifest
    "karpenter"              = local.karpenter_manifest
    "kube_admin_binding" = templatefile("${path.module}/templates/kube-admin-binding.yaml.tpl", {
      user_ocids = var.kube_exec_admin_user_ocids
    })
    "metrics_server"       = local.metrics_server_manifest
    "mpi_operator"         = local.mpi_operator_manifest_content
    "multus"               = local.multus_manifest_content
    "prometheus.crds"      = try(join("\n", local.prometheus_helm_crds), null)
    "prometheus.manifest"  = local.prometheus_helm_manifest
    "rdma_cni_plugin"      = local.rdma_cni_plugin_manifest_content
    "sriov_cni_plugin"     = local.sriov_cni_plugin_manifest_content
    "sriov_device_plugin"  = local.sriov_device_plugin_manifest_content
    "whereabouts.ippools"  = local.whereabouts_ippools_content
    "whereabouts.overlap"  = local.whereabouts_overlap_res_content
    "whereabouts.manifest" = local.whereabouts_manifest_content
  }

  kube_exec_commands = {
    argocd = compact([
      contains(["kube-system", "default"], var.argocd_namespace) ? null : format(local.kubectl_create_missing_ns, var.argocd_namespace),
      format(local.kubectl_apply_server_file, local.argocd_manifest_path),
    ])
    cilium = compact([
      contains(["kube-system", "default"], var.cilium_namespace) ? null : format(local.kubectl_create_missing_ns, var.cilium_namespace),
      format(local.kubectl_apply_server_ns_file, var.cilium_namespace, local.cilium_helm_crds_file),
      format(local.helm_upgrade_install, "cilium", "cilium", local.cilium_helm_repository, var.cilium_helm_version, var.cilium_namespace, local.cilium_helm_values_override_file),
    ])
    cluster_autoscaler = [format(local.kubectl_apply_file, local.cluster_autoscaler_manifest_path)]
    dcgm_exporter = compact([
      contains(["kube-system", "default"], var.dcgm_exporter_namespace) ? null : format(local.kubectl_create_missing_ns, var.dcgm_exporter_namespace),
      format(local.kubectl_apply_server_file, local.dcgm_exporter_helm_crds_file),
      format(local.kubectl_apply_server_file, local.dcgm_exporter_helm_manifest_file),
    ])
    gatekeeper = [format(local.kubectl_apply_server_file, local.gatekeeper_manifest_path)]
    karpenter = compact([
      contains(["kube-system", "default"], var.karpenter_namespace) ? null : format(local.kubectl_create_missing_ns, var.karpenter_namespace),
      format(local.kubectl_apply_server_file, local.karpenter_manifest_path),
    ])
    kube_admin_binding = [format(local.kubectl_apply_file, local.kube_exec_file_path["kube_admin_binding"])]
    metrics_server = compact([
      contains(["kube-system", "default"], var.metrics_server_namespace) ? null : format(local.kubectl_create_missing_ns, var.metrics_server_namespace),
      format(local.kubectl_apply_server_file, local.metrics_server_manifest_path),
    ])
    mpi_operator = [format(local.kubectl_apply_file, local.mpi_operator_manifest_path)]
    multus       = [format(local.kubectl_apply_file, local.multus_manifest_path)]
    prometheus = compact([
      contains(["kube-system", "default"], var.prometheus_namespace) ? null : format(local.kubectl_create_missing_ns, var.prometheus_namespace),
      format(local.kubectl_apply_server_file, local.prometheus_helm_crds_file),
      format(local.kubectl_apply_server_file, local.prometheus_helm_manifest_file),
    ])
    rdma_cni_plugin     = [format(local.kubectl_apply_file, local.rdma_cni_plugin_manifest_path)]
    sriov_cni_plugin    = [format(local.kubectl_apply_file, local.sriov_cni_plugin_manifest_path)]
    sriov_device_plugin = [format(local.kubectl_apply_file, local.sriov_device_plugin_manifest_path)]
    whereabouts = [
      format("${local.kubectl} apply -f %s -f %s -f %s", local.whereabouts_ippools_path, local.whereabouts_overlap_res_path, local.whereabouts_manifest_path),
    ]
  }

  # Same values as the triggers of the remote resources.
  kube_exec_triggers = {
    argocd = { manifest_md5 = try(md5(local.argocd_manifest), null) }
    cilium = {
      helm_version = var.cilium_helm_version
      crds_md5     = try(md5(join("\n", local.cilium_helm_crds)), null)
      manifest_md5 = try(md5(local.cilium_helm_values_override_yaml), null)
      reapply      = var.cilium_reapply ? uuid() : null
    }
    cluster_autoscaler = { manifest_md5 = try(md5(local.cluster_autoscaler_manifest), null) }
    dcgm_exporter = {
      helm_version = var.dcgm_exporter_helm_version
      crds_md5     = try(md5(join("\n", local.dcgm_exporter_helm_crds)), null)
      manifest_md5 = try(md5(local.dcgm_exporter_helm_manifest), null)
      reapply      = var.dcgm_exporter_reapply ? uuid() : null
    }
    gatekeeper     = { manifest_md5 = try(md5(local.gatekeeper_manifest), null) }
    karpenter      = { manifest_md5 = try(md5(local.karpenter_manifest), null) }
    metrics_server = { manifest_md5 = try(md5(local.metrics_server_manifest), null) }
    mpi_operator = {
      mpi_operator_deployment_url = local.mpi_operator_deployment_url
      mpi_operator_deployment_md5 = try(md5(local.mpi_operator_manifest_content), null)
    }
    multus = {
      multus_daemonset_url = local.multus_daemonset_url
      multus_daemonset_md5 = try(md5(local.multus_manifest_content), null)
    }
    prometheus = {
      helm_version = var.prometheus_helm_version
      crds_md5     = try(md5(join("\n", local.prometheus_helm_crds)), null)
      manifest_md5 = try(md5(local.prometheus_helm_manifest), null)
      reapply      = var.prometheus_reapply ? uuid() : null
    }
    rdma_cni_plugin = {
      rdma_cni_plugin_daemonset_url = local.rdma_cni_plugin_daemonset_url
      rdma_cni_plugin_daemonset_md5 = try(md5(local.rdma_cni_plugin_manifest_content), null)
    }
    sriov_cni_plugin = {
      sriov_cni_plugin_daemonset_url = local.sriov_cni_plugin_daemonset_url
      sriov_cni_plugin_daemonset_md5 = try(md5(local.sriov_cni_plugin_manifest_content), null)
    }
    sriov_device_plugin = {
      sriov_device_plugin_daemonset_url = local.sriov_device_plugin_daemonset_url
      sriov_device_plugin_daemonset_md5 = try(md5(local.sriov_device_plugin_manifest_content), null)
    }
    whereabouts = {
      whereabouts_ippools_url     = local.whereabouts_ippools_url
      whereabouts_overlap_res_url = local.whereabouts_overlap_res_url
      whereabouts_daemonset_url   = local.whereabouts_daemonset_url
      whereabouts_ippools_md5     = try(md5(local.whereabouts_ippools_content), null)
      whereabouts_overlap_res_md5 = try(md5(local.whereabouts_overlap_res_content), null)
      whereabouts_daemonset_md5   = try(md5(local.whereabouts_manifest_content), null)
    }
  }

  # Downloaded manifests: an HTTP error body must not reach kubectl.
  kube_exec_http_status = {
    mpi_operator        = [local.mpi_operator_manifest_status_code]
    multus              = [local.multus_manifest_status_code]
    rdma_cni_plugin     = [local.rdma_cni_plugin_manifest_status_code]
    sriov_cni_plugin    = [local.sriov_cni_plugin_manifest_status_code]
    sriov_device_plugin = [local.sriov_device_plugin_manifest_status_code]
    whereabouts = [
      local.whereabouts_ippools_status_code,
      local.whereabouts_overlap_res_status_code,
      local.whereabouts_manifest_status_code,
    ]
  }

  kube_exec_service_accounts = (var.kube_exec_local && var.create_service_account
    ? merge(local.sa_with_cluster_role_bindings, local.sa_with_role_bindings)
    : {}
  )
}

# Never reference this resource from a trigger: a new runner recreates the files without any change in content.
# Never add it to a module depends_on: the helm_template data sources would be deferred and every md5 unknown.
resource "local_sensitive_file" "kube_exec_manifest" {
  for_each = var.kube_exec_local ? toset([
    for key, owner in local.kube_exec_file_owner : key if local.kube_exec_enabled[owner]
  ]) : toset([])

  filename             = local.kube_exec_file_path[each.key]
  content              = local.kube_exec_file_content[each.key]
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "null_resource" "kube_exec_apply" {
  for_each = var.kube_exec_local ? setsubtract([
    for extension, enabled in local.kube_exec_enabled : extension if enabled
  ], local.kube_exec_ordered) : toset([])

  depends_on = [local_sensitive_file.kube_exec_manifest]

  triggers = merge(local.kube_exec_triggers[each.key], { cluster_id = var.cluster_id })

  provisioner "local-exec" {
    interpreter = local.kube_exec_interpreter
    command     = join("\n", local.kube_exec_commands[each.key])
  }

  lifecycle {
    precondition {
      condition     = alltrue([for status in lookup(local.kube_exec_http_status, each.key, []) : status == 200])
      error_message = "Error retrieving the manifest of ${each.key}: status code is not 200."
    }
  }
}

resource "null_resource" "kube_exec_apply_prometheus" {
  count      = var.kube_exec_local && var.prometheus_install ? 1 : 0
  depends_on = [local_sensitive_file.kube_exec_manifest]

  triggers = merge(local.kube_exec_triggers["prometheus"], { cluster_id = var.cluster_id })

  provisioner "local-exec" {
    interpreter = local.kube_exec_interpreter
    command     = join("\n", local.kube_exec_commands["prometheus"])
  }
}

resource "null_resource" "kube_exec_apply_cilium" {
  count      = var.kube_exec_local && var.cilium_install ? 1 : 0
  depends_on = [local_sensitive_file.kube_exec_manifest, null_resource.kube_exec_apply_prometheus]

  triggers = merge(local.kube_exec_triggers["cilium"], { cluster_id = var.cluster_id })

  provisioner "local-exec" {
    interpreter = local.kube_exec_interpreter
    command     = join("\n", local.kube_exec_commands["cilium"])
  }

  lifecycle {
    precondition {
      condition     = var.cni_type == "flannel"
      error_message = "Incompatible cni_type for installation - must be 'flannel'."
    }
  }
}

resource "null_resource" "service_account_local" {
  for_each = local.kube_exec_service_accounts

  triggers = {
    always_run = timestamp()
    cluster_id = var.cluster_id
  }

  provisioner "local-exec" {
    interpreter = local.kube_exec_interpreter
    command = templatefile("${path.module}/templates/service-account-local.sh.tpl", {
      sa_name              = each.value.sa_name
      sa_namespace         = each.value.sa_namespace
      secret_name          = "${each.value.sa_name}-token-secret"
      cluster_role         = lookup(each.value, "sa_cluster_role", "")
      cluster_role_binding = coalesce(lookup(each.value, "sa_cluster_role_binding", null), "none")
      role                 = lookup(each.value, "sa_role", "")
      role_binding         = coalesce(lookup(each.value, "sa_role_binding", null), "none")
      token_file           = "${local.kube_exec_dir}/sa-token-${each.value.sa_name}-${each.value.sa_namespace}"
    })
  }
}

# Last on purpose: nothing in this apply depends on it, so removing the running identity cannot interrupt other steps.
resource "null_resource" "kube_exec_admin_binding" {
  count = var.kube_exec_local ? 1 : 0

  depends_on = [
    local_sensitive_file.kube_exec_manifest,
    null_resource.kube_exec_apply,
    null_resource.kube_exec_apply_cilium,
    null_resource.service_account_local,
  ]

  triggers = {
    user_ocids = join(",", sort(var.kube_exec_admin_user_ocids))
    cluster_id = var.cluster_id
  }

  provisioner "local-exec" {
    interpreter = local.kube_exec_interpreter
    command     = join("\n", local.kube_exec_commands["kube_admin_binding"])
  }
}
