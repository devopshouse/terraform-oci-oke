# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  sa_token_file_crb = {
    for k, v in local.sa_with_cluster_role_bindings : k => "/tmp/terraform-sa-token-${v.sa_name}-${v.sa_namespace}.txt"
  }
  sa_token_file_rb = {
    for k, v in local.sa_with_role_bindings : k => "/tmp/terraform-sa-token-${v.sa_name}-${v.sa_namespace}.txt"
  }
}

# Resource to retrieve service account token for cluster role bindings
resource "null_resource" "service_account_token_retrieve_crb" {
  for_each = var.create_service_account ? local.sa_with_cluster_role_bindings : {}

  triggers = {
    service_account_id = null_resource.service_account_token_crb[each.key].id
    # Force update when code changes - using kubectl create token method
    token_method = "kubectl_create_token_v1"

    # Parameters ignored as triggers in the life_cycle block. Required to establish connections.
    # Using MD5 hashes to avoid exposing sensitive values in plan output
    bastion_host        = var.use_bastion ? var.bastion_host : null
    bastion_user        = var.use_bastion ? var.bastion_user : null
    bastion_private_key_md5 = var.use_bastion ? md5(var.ssh_private_key) : null
    ssh_private_key_md5     = md5(var.ssh_private_key)
    operator_host           = var.operator_host
    operator_user           = var.operator_user
  }

  connection {
    bastion_host        = var.use_bastion ? var.bastion_host : null
    bastion_user        = var.use_bastion ? var.bastion_user : null
    bastion_private_key = var.use_bastion ? var.ssh_private_key : null
    host                = var.operator_host
    user                = var.operator_user
    private_key         = var.ssh_private_key
    timeout             = "10m"
    type                = "ssh"
  }

  provisioner "remote-exec" {
    inline = [
      "TOKEN=$(kubectl create token -n ${each.value.sa_namespace} ${each.value.sa_name} --duration=8760h 2>/dev/null || kubectl get sa -n ${each.value.sa_namespace} ${each.value.sa_name} -o jsonpath='{.secrets[0].name}' 2>/dev/null | xargs -I {} kubectl get secret -n ${each.value.sa_namespace} {} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo '')",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'Waiting for service account token...' >&2",
      "  sleep 5",
      "  TOKEN=$(kubectl create token -n ${each.value.sa_namespace} ${each.value.sa_name} --duration=8760h 2>/dev/null || kubectl get sa -n ${each.value.sa_namespace} ${each.value.sa_name} -o jsonpath='{.secrets[0].name}' 2>/dev/null | xargs -I {} kubectl get secret -n ${each.value.sa_namespace} {} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo '')",
      "fi",
      "echo \"$TOKEN\" > /tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'ERROR: Failed to retrieve service account token' >&2",
      "fi"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      SSH_KEY_FILE=$(mktemp)
      echo "${var.ssh_private_key}" > "$SSH_KEY_FILE"
      chmod 600 "$SSH_KEY_FILE"
      
      BASTION_HOST="${var.bastion_host != null ? var.bastion_host : ""}"
      BASTION_USER="${var.bastion_user != null ? var.bastion_user : ""}"
      
      if ${var.use_bastion} && [ -n "$BASTION_HOST" ] && [ -n "$BASTION_USER" ]; then
        scp -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -i $SSH_KEY_FILE $BASTION_USER@$BASTION_HOST" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_crb[each.key]} 2>/dev/null || echo '' > ${local.sa_token_file_crb[each.key]}
      else
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_crb[each.key]} 2>/dev/null || echo '' > ${local.sa_token_file_crb[each.key]}
      fi
      rm -f "$SSH_KEY_FILE"
    EOT
  }

  depends_on = [
    null_resource.service_account_token_crb
  ]

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["bastion_private_key_md5"],
      triggers["ssh_private_key_md5"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}

# Resource to retrieve service account token for role bindings
resource "null_resource" "service_account_token_retrieve_rb" {
  for_each = var.create_service_account ? local.sa_with_role_bindings : {}

  triggers = {
    service_account_id = null_resource.service_account_token_rb[each.key].id
    # Force update when code changes - using kubectl create token method
    token_method = "kubectl_create_token_v1"

    # Parameters ignored as triggers in the life_cycle block. Required to establish connections.
    bastion_host        = var.use_bastion ? var.bastion_host : null
    bastion_user        = var.use_bastion ? var.bastion_user : null
    bastion_private_key = var.use_bastion ? var.ssh_private_key : null
    ssh_private_key     = var.ssh_private_key
    operator_host       = var.operator_host
    operator_user       = var.operator_user
  }

  connection {
    bastion_host        = self.triggers.bastion_host
    bastion_user        = self.triggers.bastion_user
    bastion_private_key = self.triggers.bastion_private_key
    host                = self.triggers.operator_host
    user                = self.triggers.operator_user
    private_key         = self.triggers.ssh_private_key
    timeout             = "10m"
    type                = "ssh"
  }

  provisioner "remote-exec" {
    inline = [
      "TOKEN=$(kubectl create token -n ${each.value.sa_namespace} ${each.value.sa_name} --duration=8760h 2>/dev/null || kubectl get sa -n ${each.value.sa_namespace} ${each.value.sa_name} -o jsonpath='{.secrets[0].name}' 2>/dev/null | xargs -I {} kubectl get secret -n ${each.value.sa_namespace} {} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo '')",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'Waiting for service account token...' >&2",
      "  sleep 5",
      "  TOKEN=$(kubectl create token -n ${each.value.sa_namespace} ${each.value.sa_name} --duration=8760h 2>/dev/null || kubectl get sa -n ${each.value.sa_namespace} ${each.value.sa_name} -o jsonpath='{.secrets[0].name}' 2>/dev/null | xargs -I {} kubectl get secret -n ${each.value.sa_namespace} {} -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo '')",
      "fi",
      "echo \"$TOKEN\" > /tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'ERROR: Failed to retrieve service account token' >&2",
      "fi"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      SSH_KEY_FILE=$(mktemp)
      echo "${var.ssh_private_key}" > "$SSH_KEY_FILE"
      chmod 600 "$SSH_KEY_FILE"
      
      if ${var.use_bastion} && [ -n "${try(var.bastion_host, "")}" ] && [ -n "${try(var.bastion_user, "")}" ]; then
        scp -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -i $SSH_KEY_FILE ${var.bastion_user}@${var.bastion_host}" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_rb[each.key]} 2>/dev/null || echo '' > ${local.sa_token_file_rb[each.key]}
      else
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_rb[each.key]} 2>/dev/null || echo '' > ${local.sa_token_file_rb[each.key]}
      fi
      rm -f "$SSH_KEY_FILE"
    EOT
  }

  depends_on = [
    null_resource.service_account_token_rb
  ]

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["bastion_private_key_md5"],
      triggers["ssh_private_key_md5"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}

# Data source to read tokens from local files
data "local_file" "service_account_token_crb" {
  for_each = var.create_service_account ? local.sa_with_cluster_role_bindings : {}
  
  filename = local.sa_token_file_crb[each.key]
  
  depends_on = [
    null_resource.service_account_token_retrieve_crb
  ]
}

data "local_file" "service_account_token_rb" {
  for_each = var.create_service_account ? local.sa_with_role_bindings : {}
  
  filename = local.sa_token_file_rb[each.key]
  
  depends_on = [
    null_resource.service_account_token_retrieve_rb
  ]
}

# Output: Service account tokens
output "service_account_tokens" {
  description = "Map of service account names to their tokens"
  value = merge(
    {
      for k, v in local.sa_with_cluster_role_bindings : k => try(
        trimspace(data.local_file.service_account_token_crb[k].content),
        ""
      )
    },
    {
      for k, v in local.sa_with_role_bindings : k => try(
        trimspace(data.local_file.service_account_token_rb[k].content),
        ""
      )
    }
  )
  sensitive = true
}

