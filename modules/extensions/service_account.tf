# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  sa_with_cluster_role_bindings = {
    for k, v in var.service_accounts : k => v
    if lookup(v, "sa_cluster_role_binding", null) != null
  }
  sa_with_role_bindings = {
    for k, v in var.service_accounts : k => v
    if lookup(v, "sa_role_binding", null) != null
  }
}

resource "null_resource" "service_account_crb" {
  for_each = var.create_service_account ? local.sa_with_cluster_role_bindings : {}

  triggers = {
    service_account_name                 = each.value.sa_name
    service_account_namespace            = each.value.sa_namespace
    service_account_cluster_role         = each.value.sa_cluster_role
    service_account_cluster_role_binding = each.value.sa_cluster_role_binding
    cluster_private_endpoint             = var.cluster_private_endpoint

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
      "kubectl get ns ${self.triggers.service_account_namespace} || kubectl create ns ${self.triggers.service_account_namespace}",
      "kubectl create sa -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_name}",
      "kubectl create clusterrolebinding ${self.triggers.service_account_cluster_role_binding} --clusterrole=${self.triggers.service_account_cluster_role} --serviceaccount=${self.triggers.service_account_namespace}:${self.triggers.service_account_name}"
    ]
  }

  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue
    inline = [
      "kubectl delete clusterrolebinding ${self.triggers.service_account_cluster_role_binding}",
      "kubectl delete sa -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_name}"
    ]
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}

resource "null_resource" "service_account_rb" {
  for_each = var.create_service_account ? local.sa_with_role_bindings : {}

  triggers = {
    service_account_name         = each.value.sa_name
    service_account_namespace    = each.value.sa_namespace
    service_account_cluster_role = each.value.sa_cluster_role
    service_account_role         = lookup(each.value, "sa_role", "")
    service_account_role_binding = each.value.sa_role_binding
    cluster_private_endpoint     = var.cluster_private_endpoint

    # Parameters ignored as triggers in the life_cycle block. Required to establish connections.
    bastion_host    = var.bastion_host
    bastion_user    = var.bastion_user
    ssh_private_key = var.ssh_private_key
    operator_host   = var.operator_host
    operator_user   = var.operator_user
  }

  connection {
    bastion_host        = self.triggers.bastion_host
    bastion_user        = self.triggers.bastion_user
    bastion_private_key = self.triggers.ssh_private_key
    host                = self.triggers.operator_host
    user                = self.triggers.operator_user
    private_key         = self.triggers.ssh_private_key
    timeout             = "10m"
    type                = "ssh"
  }

  provisioner "remote-exec" {
    inline = [
      "kubectl get ns ${self.triggers.service_account_namespace} || kubectl create ns ${self.triggers.service_account_namespace}",
      "kubectl create sa -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_name}",
      self.triggers.service_account_role != "" ?
      "kubectl create rolebinding -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_role_binding} --role=${self.triggers.service_account_role} --serviceaccount=${self.triggers.service_account_namespace}:${self.triggers.service_account_name}" :
      "kubectl create rolebinding -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_role_binding} --clusterrole=${self.triggers.service_account_cluster_role} --serviceaccount=${self.triggers.service_account_namespace}:${self.triggers.service_account_name}"
    ]
  }

  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue
    inline = [
      "kubectl delete rolebinding -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_role_binding}",
      "kubectl delete sa -n ${self.triggers.service_account_namespace} ${self.triggers.service_account_name}"
    ]
  }

  lifecycle {
    ignore_changes = [
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["ssh_private_key"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}

# Resource to get service account token for cluster role bindings
resource "null_resource" "service_account_token_crb" {
  for_each = var.create_service_account ? local.sa_with_cluster_role_bindings : {}

  triggers = {
    service_account_name      = each.value.sa_name
    service_account_namespace = each.value.sa_namespace
    # Re-run when the service account is created/updated
    service_account_id = null_resource.service_account_crb[each.key].id
    # Force update when code changes - using secret-based token method (permanent token)
    token_method = "secret_based_token_v1"

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
      "sleep 5", # Wait for service account to be ready
      "SECRET_NAME=\"${self.triggers.service_account_name}-token-secret\"",
      "# Create secret of type service-account-token if it doesn't exist",
      "if ! kubectl get secret -n ${self.triggers.service_account_namespace} $SECRET_NAME >/dev/null 2>&1; then",
      "  cat <<EOF | kubectl apply -f -",
      "apiVersion: v1",
      "kind: Secret",
      "metadata:",
      "  name: $SECRET_NAME",
      "  namespace: ${self.triggers.service_account_namespace}",
      "  annotations:",
      "    kubernetes.io/service-account.name: ${self.triggers.service_account_name}",
      "type: kubernetes.io/service-account-token",
      "EOF",
      "fi",
      "# Wait for Kubernetes to populate the token",
      "sleep 10",
      "TOKEN=$(kubectl get secret -n ${self.triggers.service_account_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'Waiting for service account token to be populated...' >&2",
      "  sleep 15",
      "  TOKEN=$(kubectl get secret -n ${self.triggers.service_account_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "fi",
      "if [ -n \"$TOKEN\" ]; then",
      "  echo \"$TOKEN\" > /tmp/sa-token-${self.triggers.service_account_name}-${self.triggers.service_account_namespace}.txt",
      "else",
      "  echo 'ERROR: Failed to retrieve token from secret for service account' >&2",
      "  echo '' > /tmp/sa-token-${self.triggers.service_account_name}-${self.triggers.service_account_namespace}.txt",
      "fi"
    ]
  }

  depends_on = [
    null_resource.service_account_crb
  ]

  lifecycle {
    ignore_changes = [
      triggers["service_account_id"],
      triggers["token_method"],
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["bastion_private_key_md5"],
      triggers["ssh_private_key_md5"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}

# Resource to get service account token for role bindings
resource "null_resource" "service_account_token_rb" {
  for_each = var.create_service_account ? local.sa_with_role_bindings : {}

  triggers = {
    service_account_name      = each.value.sa_name
    service_account_namespace = each.value.sa_namespace
    # Re-run when the service account is created/updated
    service_account_id = null_resource.service_account_rb[each.key].id
    # Force update when code changes - using secret-based token method (permanent token)
    token_method = "secret_based_token_v1"

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
      "sleep 5", # Wait for service account to be ready
      "SECRET_NAME=\"${self.triggers.service_account_name}-token-secret\"",
      "# Create secret of type service-account-token if it doesn't exist",
      "if ! kubectl get secret -n ${self.triggers.service_account_namespace} $SECRET_NAME >/dev/null 2>&1; then",
      "  cat <<EOF | kubectl apply -f -",
      "apiVersion: v1",
      "kind: Secret",
      "metadata:",
      "  name: $SECRET_NAME",
      "  namespace: ${self.triggers.service_account_namespace}",
      "  annotations:",
      "    kubernetes.io/service-account.name: ${self.triggers.service_account_name}",
      "type: kubernetes.io/service-account-token",
      "EOF",
      "fi",
      "# Wait for Kubernetes to populate the token",
      "sleep 10",
      "TOKEN=$(kubectl get secret -n ${self.triggers.service_account_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "if [ -z \"$TOKEN\" ]; then",
      "  echo 'Waiting for service account token to be populated...' >&2",
      "  sleep 15",
      "  TOKEN=$(kubectl get secret -n ${self.triggers.service_account_namespace} $SECRET_NAME -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || echo '')",
      "fi",
      "if [ -n \"$TOKEN\" ]; then",
      "  echo \"$TOKEN\" > /tmp/sa-token-${self.triggers.service_account_name}-${self.triggers.service_account_namespace}.txt",
      "else",
      "  echo 'ERROR: Failed to retrieve token from secret for service account' >&2",
      "  echo '' > /tmp/sa-token-${self.triggers.service_account_name}-${self.triggers.service_account_namespace}.txt",
      "fi"
    ]
  }

  depends_on = [
    null_resource.service_account_rb
  ]

  lifecycle {
    ignore_changes = [
      triggers["service_account_id"],
      triggers["token_method"],
      triggers["bastion_host"],
      triggers["bastion_user"],
      triggers["bastion_private_key_md5"],
      triggers["ssh_private_key_md5"],
      triggers["operator_host"],
      triggers["operator_user"]
    ]
  }
}