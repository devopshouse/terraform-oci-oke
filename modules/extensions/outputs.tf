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
    always_run         = timestamp()
    service_account_id = null_resource.service_account_token_crb[each.key].id
    token_method       = "permanent_secret_token_v1"

    # Parameters ignored as triggers in the life_cycle block. Required to establish connections.
    # Using MD5 hashes to avoid exposing sensitive values in plan output
    bastion_host            = var.use_bastion ? var.bastion_host : null
    bastion_user            = var.use_bastion ? var.bastion_user : null
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
      "# Always use the permanent token from the service-account-token secret",
      "# This ensures we get a permanent token (no expiration) instead of a temporary one",
      "SECRET_NAME=\"${each.value.sa_name}-token-secret\"",
      "# Ensure the secret exists (it should already exist from service_account_token_crb)",
      "if ! kubectl get secret -n ${each.value.sa_namespace} $SECRET_NAME >/dev/null 2>&1; then",
      "  cat <<EOF | kubectl apply -f -",
      "apiVersion: v1",
      "kind: Secret",
      "metadata:",
      "  name: $SECRET_NAME",
      "  namespace: ${each.value.sa_namespace}",
      "  annotations:",
      "    kubernetes.io/service-account.name: ${each.value.sa_name}",
      "type: kubernetes.io/service-account-token",
      "EOF",
      "  sleep 10",
      "fi",
      "# Get the permanent token from the secret (always fetch current token for idempotency)",
      "TOKEN=$(kubectl get secret -n ${each.value.sa_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'Waiting for service account token to be populated...' >&2",
      "  sleep 15",
      "  TOKEN=$(kubectl get secret -n ${each.value.sa_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "fi",
      "if [ -n \"$TOKEN\" ]; then",
      "  echo \"$TOKEN\" > /tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt",
      "else",
      "  echo 'ERROR: Failed to retrieve permanent token from secret for service account' >&2",
      "  echo '' > /tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt",
      "fi"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      SSH_KEY_FILE=$(mktemp)
      chmod 600 "$SSH_KEY_FILE"
      printf '%s' "${var.ssh_private_key}" > "$SSH_KEY_FILE"

      BASTION_HOST="${var.bastion_host != null ? var.bastion_host : ""}"
      BASTION_USER="${var.bastion_user != null ? var.bastion_user : ""}"
      
      if ${var.use_bastion} && [ -n "$BASTION_HOST" ] && [ -n "$BASTION_USER" ]; then
        scp -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -i $SSH_KEY_FILE $BASTION_USER@$BASTION_HOST" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_crb[each.key]} || { echo "ERROR: scp failed to retrieve token for ${each.value.sa_name}" >&2; rm -f "$SSH_KEY_FILE"; exit 1; }
      else
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_crb[each.key]} || { echo "ERROR: scp failed to retrieve token for ${each.value.sa_name}" >&2; rm -f "$SSH_KEY_FILE"; exit 1; }
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
    always_run         = timestamp()
    service_account_id = null_resource.service_account_token_rb[each.key].id
    token_method       = "permanent_secret_token_v1"

    # Parameters ignored as triggers in the life_cycle block. Required to establish connections.
    # Using MD5 hashes to avoid exposing sensitive values in plan output
    bastion_host            = var.use_bastion ? var.bastion_host : null
    bastion_user            = var.use_bastion ? var.bastion_user : null
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
      "# Always use the permanent token from the service-account-token secret",
      "# This ensures we get a permanent token (no expiration) instead of a temporary one",
      "SECRET_NAME=\"${each.value.sa_name}-token-secret\"",
      "# Ensure the secret exists (it should already exist from service_account_token_rb)",
      "if ! kubectl get secret -n ${each.value.sa_namespace} $SECRET_NAME >/dev/null 2>&1; then",
      "  cat <<EOF | kubectl apply -f -",
      "apiVersion: v1",
      "kind: Secret",
      "metadata:",
      "  name: $SECRET_NAME",
      "  namespace: ${each.value.sa_namespace}",
      "  annotations:",
      "    kubernetes.io/service-account.name: ${each.value.sa_name}",
      "type: kubernetes.io/service-account-token",
      "EOF",
      "  sleep 10",
      "fi",
      "# Get the permanent token from the secret (always fetch current token for idempotency)",
      "TOKEN=$(kubectl get secret -n ${each.value.sa_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'Waiting for service account token to be populated...' >&2",
      "  sleep 15",
      "  TOKEN=$(kubectl get secret -n ${each.value.sa_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "fi",
      "if [ -n \"$TOKEN\" ]; then",
      "  echo \"$TOKEN\" > /tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt",
      "else",
      "  echo 'ERROR: Failed to retrieve permanent token from secret for service account' >&2",
      "  echo '' > /tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt",
      "fi"
    ]
  }

  provisioner "local-exec" {
    command = <<-EOT
      SSH_KEY_FILE=$(mktemp)
      chmod 600 "$SSH_KEY_FILE"
      printf '%s' "${var.ssh_private_key}" > "$SSH_KEY_FILE"

      if ${var.use_bastion} && [ -n "${try(var.bastion_host, "")}" ] && [ -n "${try(var.bastion_user, "")}" ]; then
        scp -o ProxyCommand="ssh -W %h:%p -o StrictHostKeyChecking=no -i $SSH_KEY_FILE ${var.bastion_user}@${var.bastion_host}" \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_rb[each.key]} || { echo "ERROR: scp failed to retrieve token for ${each.value.sa_name}" >&2; rm -f "$SSH_KEY_FILE"; exit 1; }
      else
        scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_FILE" \
            ${var.operator_user}@${var.operator_host}:/tmp/sa-token-${each.value.sa_name}-${each.value.sa_namespace}.txt \
            ${local.sa_token_file_rb[each.key]} || { echo "ERROR: scp failed to retrieve token for ${each.value.sa_name}" >&2; rm -f "$SSH_KEY_FILE"; exit 1; }
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
      triggers["operator_user"],
    ]
  }
}

# Data source to read tokens from local files
# Uses external data source to handle missing files gracefully during plan
# This allows terraform plan to work even when files don't exist yet
data "external" "service_account_token_crb" {
  for_each = var.create_service_account ? local.sa_with_cluster_role_bindings : {}

  program = ["sh", "-c", "FILEPATH='${local.sa_token_file_crb[each.key]}'; if [ -f \"$FILEPATH\" ]; then CONTENT=$(cat \"$FILEPATH\" | base64 | tr -d '\\n'); else CONTENT=\"\"; fi; echo \"{\\\"content\\\":\\\"$CONTENT\\\"}\""]

  depends_on = [
    null_resource.service_account_token_retrieve_crb
  ]
}

# Convert external data source output back to string
locals {
  service_account_token_crb_content = {
    for k, v in data.external.service_account_token_crb : k => try(
      v.result.content != "" ? base64decode(v.result.content) : "",
      ""
    )
  }
}

# Data source to read tokens from local files
# Uses external data source to handle missing files gracefully during plan
# This allows terraform plan to work even when files don't exist yet
data "external" "service_account_token_rb" {
  for_each = var.create_service_account ? local.sa_with_role_bindings : {}

  program = ["sh", "-c", "FILEPATH='${local.sa_token_file_rb[each.key]}'; if [ -f \"$FILEPATH\" ]; then CONTENT=$(cat \"$FILEPATH\" | base64 | tr -d '\\n'); else CONTENT=\"\"; fi; echo \"{\\\"content\\\":\\\"$CONTENT\\\"}\""]

  depends_on = [
    null_resource.service_account_token_retrieve_rb
  ]
}

# Convert external data source output back to string
locals {
  service_account_token_rb_content = {
    for k, v in data.external.service_account_token_rb : k => try(
      v.result.content != "" ? base64decode(v.result.content) : "",
      ""
    )
  }
}

# Output: Service account tokens
output "service_account_tokens" {
  description = "Map of service account names to their tokens"
  value = merge(
    {
      for k, v in local.sa_with_cluster_role_bindings : k => try(
        trimspace(local.service_account_token_crb_content[k]),
        ""
      )
    },
    {
      for k, v in local.sa_with_role_bindings : k => try(
        trimspace(local.service_account_token_rb_content[k]),
        ""
      )
    }
  )
  sensitive = true
}

