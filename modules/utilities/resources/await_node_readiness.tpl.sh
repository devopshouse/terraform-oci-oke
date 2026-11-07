#!/usr/bin/env bash
# Copyright (c) 2017, 2023 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl
# shellcheck disable=SC1083,SC2309,SC2050,SC2154,SC2157,SC2034 # Ignore templated/escaped/unused file variables
NODE_STATE_DIR=$(mktemp -d)
trap 'rm -rf "$${NODE_STATE_DIR}"' EXIT
export ALL_FILE="$${NODE_STATE_DIR}/all_node.active" ONE_FILE="$${NODE_STATE_DIR}/one_node.active"

function clean_node_active() {
  rm -f "$${ALL_FILE}" "$${ONE_FILE}"
}

function get_actual_node_count() {
  local nodes
  nodes=$(kubectl get --no-headers nodes 2>/dev/null) || nodes=''
  printf '%s\n' "$${nodes}" | awk 'NF && $2 !~ /NotReady/ {count++} END {print count + 0}'
}

function wait_for_active() {
  clean_node_active

  while true; do
    local actual_node_count
    actual_node_count=$(get_actual_node_count)
    if [[ $${actual_node_count} -ge ${expected_node_count} ]]; then touch "$${ALL_FILE}"; fi
    if [[ $${actual_node_count} -ge 1 ]]; then touch "$${ONE_FILE}"; fi

    if [[ -f "$${ONE_FILE}" ]] && [[ "${await_node_readiness}" == 'one' ]]; then
      echo "$(date): Ready with $${actual_node_count} node(s)" >&2
      break
    fi

    if [[ -f "$${ALL_FILE}" ]] && [[ "${await_node_readiness}" == 'all' ]]; then
      echo "$(date): Ready with $${actual_node_count} node(s)" >&2
      break
    fi

    echo "$(date): Waiting for ${await_node_readiness} of ${expected_node_count} node(s) to become ready ($${actual_node_count} found)" >&2
    sleep 30
  done
}

if [[ ${expected_node_count} -ge 1 ]]; then time wait_for_active; fi