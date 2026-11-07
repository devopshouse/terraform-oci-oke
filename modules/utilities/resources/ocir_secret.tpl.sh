#!/usr/bin/env bash
# Copyright (c) 2026 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
# shellcheck disable=SC1083,SC2016,SC2034,SC2154,SC2157 # Ignore templated/escaped file variables
set -euo pipefail
umask 077

work_dir=$(mktemp -d)
trap 'rm -rf "$${work_dir}"' EXIT
config_file="$${work_dir}/config.json"

# The password stays out of process arguments: only shell builtins and pipes receive it.
password=$(oci secrets secret-bundle get --raw-output --region '${region}' --secret-id '${secret_id}' \
  --query 'data."secret-bundle-content".content' | base64 -d)
if [ -z "$${password}" ]; then
  echo "ocir-secret: secret ${secret_id} is empty" >&2
  exit 1
fi

auth=$(printf '%s:%s' '${username}' "$${password}" | base64 | tr -d '\n')
printf '{"auths":{"%s":{"username":"%s","email":"%s","auth":"%s"}}}' \
  '${registry}' '${username}' '${email_address}' "$${auth}" >"$${config_file}"

kubectl create ns '${secret_namespace}' --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic '${secret_name}' -n '${secret_namespace}' \
  --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson="$${config_file}" \
  --dry-run=client -o yaml | kubectl apply -f -
