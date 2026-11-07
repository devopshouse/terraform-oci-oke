#!/usr/bin/env bash
# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
#
# local-exec interpreter: kube-exec.sh <cluster_id> <region> <kube_endpoint> <command>
# Runs <command> against a throwaway kubeconfig, never the current context of the machine.
# Profile and auth come from the environment (OCI_CLI_PROFILE, OCI_CLI_AUTH).
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: kube-exec.sh <cluster_id> <region> <kube_endpoint> <command>" >&2
  exit 64
fi

cluster_id=$1
region=$2
kube_endpoint=$3
command=$4

api_wait_seconds=${KUBE_EXEC_API_WAIT_SECONDS:-300}
api_wait_interval=${KUBE_EXEC_API_WAIT_INTERVAL:-10}

# Same resolution order as the OCI CLI: environment, default_profile of oci_cli_rc, DEFAULT.
oci_profile=${OCI_CLI_PROFILE:-}
if [ -z "$oci_profile" ]; then
  oci_profile=$(sed -n 's/^default_profile[[:space:]]*=[[:space:]]*//p' "${OCI_CLI_RC_FILE:-$HOME/.oci/oci_cli_rc}" 2>/dev/null | head -n 1 || true)
fi
oci_profile=${oci_profile:-DEFAULT}
oci_auth=${OCI_CLI_AUTH:-api_key}

access_hint="Check the route to the ${kube_endpoint} of the cluster, control_plane_allowed_cidrs and the OCI credential (profile ${oci_profile}, auth ${oci_auth})."

die() {
  echo "kube-exec: $*" >&2
  exit 1
}

required_tools="oci kubectl"
case "$command" in
  *helm\ *) required_tools="$required_tools helm" ;;
esac
for tool in $required_tools; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found in PATH."
done

echo "kube-exec: cluster ${cluster_id}, region ${region}, endpoint ${kube_endpoint}, OCI profile ${oci_profile}, auth ${oci_auth}"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export KUBECONFIG="$work_dir/kubeconfig"

oci --connection-timeout 10 --read-timeout 60 ce cluster create-kubeconfig \
  --cluster-id "$cluster_id" \
  --region "$region" \
  --file "$KUBECONFIG" \
  --kube-endpoint "$kube_endpoint" \
  --token-version 2.0.0 >/dev/null || die "failed to create kubeconfig for $cluster_id. $access_hint"

# A bounded number of attempts would not bound the time if one call blocks, so the deadline is measured.
deadline=$((SECONDS + api_wait_seconds))
until api_error=$(kubectl --request-timeout=10s get --raw /version 2>&1 >/dev/null); do
  if [ "$SECONDS" -ge "$deadline" ]; then
    die "API not reachable after ${api_wait_seconds}s. $access_hint Last error: $api_error"
  fi
  sleep "$api_wait_interval"
done

can_i=$(kubectl --request-timeout=30s auth can-i '*' '*' 2>/dev/null || true)
if [ "$can_i" != "yes" ]; then
  die "the current OCI identity is not cluster-admin (can-i = '${can_i:-error}'). $access_hint"
fi

rc=0
bash -e -o pipefail -c "$command" || rc=$?
exit "$rc"
