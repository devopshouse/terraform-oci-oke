# Copyright (c) 2017, 2023 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Retrieve object storage namespace for secret
data "oci_objectstorage_namespace" "object_storage_namespace" {
  count = coalesce(var.ocir_secret_id, "none") != "none" ? 1 : 0
}

locals {
  region_registry   = "${var.region}.ocir.io"
  tenancy_namespace = one(data.oci_objectstorage_namespace.object_storage_namespace[*].namespace)

  ocir_secret_remote_script = "/home/${var.operator_user}/ocir_secret.sh"
  ocir_secret_script = templatefile("${path.module}/resources/ocir_secret.tpl.sh", {
    email_address    = coalesce(var.ocir_email_address, "none")
    registry         = local.region_registry
    region           = var.region
    secret_id        = coalesce(var.ocir_secret_id, "none")
    secret_name      = coalesce(var.ocir_secret_name, "none")
    secret_namespace = coalesce(var.ocir_secret_namespace, "none")
    username         = join("/", compact([local.tenancy_namespace, var.ocir_username]))
  })

  ocir_secret_config_complete = alltrue([
    local.region_registry != null,
    local.tenancy_namespace != null,
    var.ocir_email_address != null,
    var.ocir_secret_name != null,
    var.ocir_secret_namespace != null,
    var.ocir_username != null,
  ])
}

resource "null_resource" "ocir_secret" {
  count    = coalesce(var.ocir_secret_id, "none") != "none" && !var.kube_exec_local ? 1 : 0
  triggers = { always_run = timestamp() }

  connection {
    bastion_host        = var.bastion_host
    bastion_user        = var.bastion_user
    bastion_private_key = var.ssh_private_key
    host                = var.operator_host
    user                = var.operator_user
    private_key         = var.ssh_private_key
    timeout             = "40m"
    type                = "ssh"
  }

  provisioner "file" {
    content     = local.ocir_secret_script
    destination = local.ocir_secret_remote_script
  }

  provisioner "remote-exec" {
    inline = ["bash ${local.ocir_secret_remote_script}"]
  }

  lifecycle {
    precondition {
      condition     = local.ocir_secret_config_complete
      error_message = "Missing required configuration for OCIR; check variables."
    }
  }
}

resource "null_resource" "ocir_secret_local" {
  count = coalesce(var.ocir_secret_id, "none") != "none" && var.kube_exec_local ? 1 : 0
  triggers = {
    always_run = timestamp()
    cluster_id = var.cluster_id
  }

  provisioner "local-exec" {
    interpreter = local.kube_exec_interpreter
    command     = local.ocir_secret_script
  }

  lifecycle {
    precondition {
      condition     = local.ocir_secret_config_complete
      error_message = "Missing required configuration for OCIR; check variables."
    }
  }
}
