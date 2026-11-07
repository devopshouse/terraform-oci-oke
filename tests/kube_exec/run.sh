#!/usr/bin/env bash
# Tests without a cluster: simulated oci, kubectl and helm in PATH record arguments and answer per case.
# They never reach OCI or a cluster: the run aborts if a real CLI would be used.
# Usage: tests/kube_exec/run.sh [--render-only DIR | --rendered DIR]
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STUBS="$ROOT/tests/kube_exec/stubs"
SCRIPT="$ROOT/scripts/kube-exec.sh"
BASH_BIN=${BASH_BIN:-$BASH}
MODE=${1:-}
RENDER_DIR=${2:-}
WORK=$(mktemp -d)
failures=0
checks=0

kill_tree() {
  local child
  for child in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$child"; done
  kill -9 "$1" 2>/dev/null
}

# A hung case must not hold the run forever.
(
  sleep "${KUBE_EXEC_TEST_TIMEOUT:-300}"
  echo "FAIL watchdog: run exceeded the time limit" >&2
  kill -TERM $$
) &
watchdog=$!
disown "$watchdog"
trap 'kill_tree "$watchdog"; rm -rf "$WORK"' EXIT
trap 'exit 124' TERM

export BASH_BIN SCRIPT
export KUBE_EXEC_API_WAIT_SECONDS=2 KUBE_EXEC_API_WAIT_INTERVAL=1
export KUBE_EXEC_TOKEN_WAIT_SECONDS=2 KUBE_EXEC_TOKEN_WAIT_INTERVAL=1
export PATH="$STUBS:$PATH"

# Second barrier: a real CLI reached by mistake finds no credential and no cluster.
unset OCI_CLI_PROFILE OCI_CLI_AUTH OCI_CLI_RC_FILE
export OCI_CLI_CONFIG_FILE=/nonexistent/oci-config KUBECONFIG=/nonexistent/kubeconfig
for tool in oci kubectl helm; do
  if [ "$(type -P "$tool")" != "$STUBS/$tool" ]; then
    echo "abort: $tool does not resolve to the simulated CLI" >&2
    exit 2
  fi
done

ok() { checks=$((checks + 1)); echo "ok   $1"; }
ko() { checks=$((checks + 1)); failures=$((failures + 1)); echo "FAIL $1"; }
check() { # description, command...
  local description=$1
  shift
  if "$@"; then ok "$description"; else ko "$description"; fi
}
no() { ! "$@"; }
called() { grep -Fq -- "$1" "$STUB_DIR/calls"; }
called_line() { grep -Fn -- "$1" "$STUB_DIR/calls" | tail -n 1 | cut -d: -f1; }
writes() { grep -E '^kubectl (create|apply|patch|annotate|label|delete|replace)' "$STUB_DIR/calls" | grep -vc 'dry-run'; }

reset() {
  STUB_DIR="$WORK/stub.$RANDOM$RANDOM"
  export STUB_DIR
  mkdir -p "$STUB_DIR/objects" "$STUB_DIR/cwd"
  : >"$STUB_DIR/calls"
}

kube_exec() { "$BASH_BIN" "$SCRIPT" ocid1.cluster.test sa-saopaulo-1 PRIVATE_ENDPOINT "$1"; }
kubeconfig_removed() { [ ! -e "$(cat "$STUB_DIR/kubeconfig_path")" ]; }

# ---------------------------------------------------------------- kube-exec.sh
test_kube_exec() {
  local out rc

  reset
  out=$(kube_exec 'printf "%s|%s" "a b" "c'\''d"' | tail -n 1) rc=$?
  check "script: success returns 0" [ "$rc" -eq 0 ]
  check "script: quotes and spaces preserved" [ "$out" = "a b|c'd" ]
  check "script: kubeconfig removed after success" kubeconfig_removed
  check "script: --file points to a temporary kubeconfig" called "--file $(dirname "$(cat "$STUB_DIR/kubeconfig_path")")/kubeconfig"
  check "script: explicit region and endpoint" called "--region sa-saopaulo-1 --file"
  check "script: oci has timeouts" called "oci --connection-timeout 10 --read-timeout 60 ce cluster create-kubeconfig"
  check "script: kubectl has request timeout" called "kubectl --request-timeout=10s get --raw /version"

  reset
  kube_exec 'kubectl get --no-headers nodes; exit 37' >/dev/null
  rc=$?
  check "script: exit code propagated" [ "$rc" -eq 37 ]
  check "script: kubeconfig removed after failure" kubeconfig_removed

  reset
  kube_exec 'false
echo must-not-run' >"$STUB_DIR/out" 2>&1
  rc=$?
  check "script: multi-line command stops at first failure" [ "$rc" -ne 0 ]
  check "script: following lines do not run" no grep -q must-not-run "$STUB_DIR/out"

  reset
  touch "$STUB_DIR/oci_fails"
  kube_exec 'touch "$STUB_DIR/ran"' >/dev/null 2>"$STUB_DIR/err"
  rc=$?
  check "script: oci failure fails" [ "$rc" -ne 0 ]
  check "script: oci failure runs nothing" [ ! -e "$STUB_DIR/ran" ]

  reset
  touch "$STUB_DIR/api_down"
  kube_exec 'touch "$STUB_DIR/ran"' >/dev/null 2>"$STUB_DIR/err"
  rc=$?
  check "script: API unavailable until deadline fails" [ "$rc" -ne 0 ]
  check "script: API error cites route and credential" grep -q 'control_plane_allowed_cidrs' "$STUB_DIR/err"
  check "script: API unavailable runs nothing" [ ! -e "$STUB_DIR/ran" ]

  reset
  echo no >"$STUB_DIR/can_i"
  kube_exec 'touch "$STUB_DIR/ran"' >/dev/null 2>"$STUB_DIR/err"
  rc=$?
  check "script: can-i = no fails" [ "$rc" -ne 0 ]
  check "script: can-i = no runs nothing" [ ! -e "$STUB_DIR/ran" ]
  check "script: kubeconfig removed after can-i = no" kubeconfig_removed

  reset
  OCI_CLI_PROFILE=from-env OCI_CLI_AUTH=security_token kube_exec 'true' >"$STUB_DIR/out" 2>&1
  check "script: profile from environment is printed" grep -q 'OCI profile from-env, auth security_token' "$STUB_DIR/out"
  mkdir -p "$WORK/home/.oci"
  printf '[OCI_CLI_SETTINGS]\ndefault_profile=from-rc\n' >"$WORK/home/.oci/oci_cli_rc"
  reset
  HOME="$WORK/home" kube_exec 'true' >"$STUB_DIR/out" 2>&1
  check "script: default_profile of oci_cli_rc is printed" grep -q 'OCI profile from-rc, auth api_key' "$STUB_DIR/out"
  reset
  HOME="$WORK/empty-home" kube_exec 'true' >"$STUB_DIR/out" 2>&1
  check "script: DEFAULT is printed without configuration" grep -q 'OCI profile DEFAULT' "$STUB_DIR/out"
  reset
  OCI_CLI_PROFILE=from-env HOME="$WORK/home" bash -c 'touch "$STUB_DIR/oci_fails"; "$BASH_BIN" "$SCRIPT" c r PRIVATE_ENDPOINT true' >/dev/null 2>"$STUB_DIR/err"
  check "script: error names the profile" grep -q 'profile from-env' "$STUB_DIR/err"

  local partial="$WORK/partial"
  mkdir -p "$partial"
  ln -sf "$STUBS/oci" "$partial/oci"
  ln -sf "$(command -v bash)" "$partial/bash"
  reset
  PATH="$partial:/usr/bin:/bin" kube_exec 'true' >/dev/null 2>"$STUB_DIR/err"
  rc=$?
  check "script: missing tool fails" [ "$rc" -ne 0 ]
  check "script: missing tool is named" grep -q 'kubectl not found' "$STUB_DIR/err"
  check "script: missing tool does not call oci" no called "create-kubeconfig"

  ln -sf "$STUBS/kubectl" "$partial/kubectl"
  reset
  PATH="$partial:/usr/bin:/bin" kube_exec 'true' >/dev/null 2>&1
  check "script: helm not required when unused" [ "$?" -eq 0 ]
  reset
  PATH="$partial:/usr/bin:/bin" kube_exec 'helm upgrade' >/dev/null 2>"$STUB_DIR/err"
  check "script: helm required when used" grep -q 'helm not found' "$STUB_DIR/err"
}

# ---------------------------------------------------------------- rendered templates
render() { # template path, output file, HCL object with the template variables
  local dir
  if [ "$MODE" = "--rendered" ]; then
    cp "$RENDER_DIR/$(basename "$2")" "$2"
    return
  fi
  dir=$(mktemp -d "$WORK/render.XXXXXX")
  cat >"$dir/main.tf" <<HCL
output "r" { value = templatefile("$1", $3) }
HCL
  (cd "$dir" && terraform init -input=false -no-color >/dev/null && terraform apply -auto-approve -input=false -no-color >/dev/null \
    && terraform output -raw r) >"$2"
  if [ "$MODE" = "--render-only" ]; then
    cp "$2" "$RENDER_DIR/"
  elif command -v shellcheck >/dev/null 2>&1; then
    case "$2" in
      */binding*) ;;
      *) check "shellcheck: rendered $(basename "$2")" shellcheck -s bash -S warning "$2" ;;
    esac
  fi
}

run_rendered() { # rendered file
  (cd "$STUB_DIR/cwd" && kube_exec "$(cat "$1")")
}

sa_setup_existing() {
  : >"$STUB_DIR/objects/namespace"
  : >"$STUB_DIR/objects/serviceaccount"
  printf 'ClusterRole/cluster-admin\nServiceAccount/kube-system/crb-sa\n' >"$STUB_DIR/objects/clusterrolebinding"
  : >"$STUB_DIR/objects/secret"
  echo kubernetes.io/service-account-token >"$STUB_DIR/secret_type"
  echo crb-sa >"$STUB_DIR/secret_sa"
  echo synthetic-sa-token >"$STUB_DIR/token"
}

test_service_account() {
  local tpl="$WORK/sa.sh" rb_tpl="$WORK/sa_rb.sh" token_file="token/sa-token" rc
  local vars='{sa_name="crb-sa", sa_namespace="kube-system", secret_name="crb-sa-token-secret", cluster_role="cluster-admin", cluster_role_binding="crb-sa-crb", role="", role_binding="none", token_file="token/sa-token"}'
  render "$ROOT/modules/extensions/templates/service-account-local.sh.tpl" "$tpl" "$vars"
  render "$ROOT/modules/extensions/templates/service-account-local.sh.tpl" "$rb_tpl" \
    '{sa_name="rb-sa", sa_namespace="apps", secret_name="rb-sa-token-secret", cluster_role="view", cluster_role_binding="none", role="reader", role_binding="rb-sa-rb", token_file="token/sa-token"}'

  reset
  echo synthetic-sa-token >"$STUB_DIR/token"
  run_rendered "$tpl" >"$STUB_DIR/out" 2>&1
  rc=$?
  check "sa: missing objects are created" [ "$rc" -eq 0 ]
  check "sa: CRB created" called "kubectl create clusterrolebinding crb-sa-crb --clusterrole=cluster-admin --serviceaccount=kube-system:crb-sa"
  check "sa: secret created with type and annotation" grep -q 'kubernetes.io/service-account.name: crb-sa' "$STUB_DIR/created_secret"
  check "sa: token file written" grep -q synthetic-sa-token "$STUB_DIR/cwd/$token_file"
  check "sa: token file mode 0600" [ -n "$(find "$STUB_DIR/cwd/$token_file" -perm 600)" ]
  check "sa: token not printed" no grep -q synthetic-sa-token "$STUB_DIR/out"
  check "sa: no temporary left behind" [ -z "$(find "$STUB_DIR/cwd/token" -name '.sa-token.*')" ]

  reset
  sa_setup_existing
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "sa: existing and correct objects pass" [ "$rc" -eq 0 ]
  check "sa: existing objects get no write" [ "$(writes)" -eq 0 ]

  reset
  sa_setup_existing
  printf 'ClusterRole/view\nServiceAccount/kube-system/crb-sa\n' >"$STUB_DIR/objects/clusterrolebinding"
  run_rendered "$tpl" >/dev/null 2>"$STUB_DIR/err"
  rc=$?
  check "sa: divergent roleRef fails" [ "$rc" -ne 0 ]
  check "sa: divergent roleRef gets no write" [ "$(writes)" -eq 0 ]
  check "sa: divergent roleRef publishes no file" [ ! -e "$STUB_DIR/cwd/$token_file" ]

  reset
  sa_setup_existing
  printf 'ClusterRole/cluster-admin\nServiceAccount/other/crb-sa\n' >"$STUB_DIR/objects/clusterrolebinding"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "sa: divergent subject fails" [ "$rc" -ne 0 ]

  reset
  sa_setup_existing
  echo Opaque >"$STUB_DIR/secret_type"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "sa: wrong secret type fails" [ "$rc" -ne 0 ]

  reset
  sa_setup_existing
  echo other-sa >"$STUB_DIR/secret_sa"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "sa: wrong secret annotation fails" [ "$rc" -ne 0 ]

  reset
  sa_setup_existing
  echo 1 >"$STUB_DIR/token_after"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "sa: slow token is awaited" [ "$rc" -eq 0 ]
  check "sa: slow token is written" grep -q synthetic-sa-token "$STUB_DIR/cwd/$token_file"

  reset
  sa_setup_existing
  rm -f "$STUB_DIR/token"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "sa: token never arriving fails" [ "$rc" -ne 0 ]
  check "sa: token never arriving publishes no file" [ ! -e "$STUB_DIR/cwd/$token_file" ]

  reset
  echo synthetic-sa-token >"$STUB_DIR/token"
  run_rendered "$rb_tpl" >/dev/null 2>&1
  rc=$?
  check "sa: role binding created" [ "$rc" -eq 0 ]
  check "sa: role binding uses --role" called "kubectl create rolebinding -n apps rb-sa-rb --role=reader --serviceaccount=apps:rb-sa"
}

test_remove_addons() {
  local tpl="$WORK/addon.sh" rc
  render "$ROOT/modules/cluster-addons/templates/remove-addon-local.sh.tpl" "$tpl" \
    '{addon_name="Flannel", cluster_id="ocid1.cluster.test", region="sa-saopaulo-1", disable_command="oci ce cluster disable-addon --addon-name Flannel --cluster-id ocid1.cluster.test --is-remove-existing-add-on true --force", custom_commands="kubectl delete ds custom"}'

  reset
  printf '["CoreDNS","Flannel"]\n' >"$STUB_DIR/addons"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "addon: listed addon is removed" [ "$rc" -eq 0 ]
  check "addon: disable-addon has explicit region" called "--force --region sa-saopaulo-1"
  check "addon: custom command runs" called "kubectl delete ds custom"

  reset
  printf '["CoreDNS"]\n' >"$STUB_DIR/addons"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "addon: absent addon is skipped" [ "$rc" -eq 0 ]
  check "addon: absent addon has no disable-addon" no called "disable-addon"
  check "addon: absent addon has no custom command" no called "kubectl delete ds custom"

  reset
  touch "$STUB_DIR/list_addons_fails"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "addon: list-addons error fails" [ "$rc" -ne 0 ]
  check "addon: list-addons error has no disable-addon" no called "disable-addon"

  reset
  printf '["Flannel"]\n' >"$STUB_DIR/addons"
  touch "$STUB_DIR/disable_addon_fails"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "addon: disable-addon error fails" [ "$rc" -ne 0 ]
  check "addon: disable-addon error skips custom command" no called "kubectl delete ds custom"
}

with_deadline() { # seconds, command...; fails if the command is still running at the deadline
  local seconds=$1 pid elapsed=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$seconds" ]; then
      kill_tree "$pid"
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

test_await_node() {
  local one="$WORK/await_one.sh" all="$WORK/await_all.sh" rc
  render "$ROOT/modules/utilities/resources/await_node_readiness.tpl.sh" "$one" '{await_node_readiness="one", expected_node_count=2}'
  render "$ROOT/modules/utilities/resources/await_node_readiness.tpl.sh" "$all" '{await_node_readiness="all", expected_node_count=2}'

  reset
  printf 'n1 Ready <none> 1d v1\nn2 NotReady <none> 1d v1\n' >"$STUB_DIR/nodes"
  with_deadline 15 run_rendered "$one" >/dev/null 2>&1
  rc=$?
  check "await: 'one' ends outside the home directory" [ "$rc" -eq 0 ]
  check "await: no state left in cwd" [ -z "$(ls -A "$STUB_DIR/cwd")" ]

  reset
  printf 'n1 Ready <none> 1d v1\nn2 Ready,SchedulingDisabled <none> 1d v1\n' >"$STUB_DIR/nodes"
  with_deadline 15 run_rendered "$all" >/dev/null 2>&1
  rc=$?
  check "await: 'all' ends outside the home directory" [ "$rc" -eq 0 ]

  reset
  printf 'n1 NotReady <none> 1d v1\n' >"$STUB_DIR/nodes"
  with_deadline 4 run_rendered "$one" >/dev/null 2>&1
  rc=$?
  check "await: keeps waiting with no ready node" [ "$rc" -eq 124 ]
}

test_ocir() {
  local tpl="$WORK/ocir.sh" rc password='synthetic"pass\word' expected
  render "$ROOT/modules/utilities/resources/ocir_secret.tpl.sh" "$tpl" \
    '{email_address="a@example.com", registry="sa-saopaulo-1.ocir.io", region="sa-saopaulo-1", secret_id="ocid1.vaultsecret.test", secret_name="ocirsecret", secret_namespace="default", username="tenancy/user"}'

  reset
  printf '%s' "$password" >"$STUB_DIR/ocir_password"
  run_rendered "$tpl" >"$STUB_DIR/out" 2>&1
  rc=$?
  expected=$(printf '%s:%s' 'tenancy/user' "$password" | base64 | tr -d '\n')
  check "ocir: secret created" [ "$rc" -eq 0 ]
  check "ocir: generic secret with dockerconfigjson type" called "--type=kubernetes.io/dockerconfigjson"
  check "ocir: username correct in the config" grep -Fq '"username":"tenancy/user"' "$STUB_DIR/dockerconfig"
  check "ocir: auth holds user and password" grep -Fq "\"auth\":\"$expected\"" "$STUB_DIR/dockerconfig"
  check "ocir: registry correct in the config" grep -Fq '"sa-saopaulo-1.ocir.io"' "$STUB_DIR/dockerconfig"
  check "ocir: password absent from arguments" no grep -Fq "$password" "$STUB_DIR/calls"
  check "ocir: base64 auth absent from arguments" no grep -Fq "$expected" "$STUB_DIR/calls"
  check "ocir: password absent from output" no grep -Fq "$password" "$STUB_DIR/out"
  check "ocir: temporary file removed after success" [ ! -e "$(cat "$STUB_DIR/dockerconfig_path")" ]

  reset
  printf '%s' "$password" >"$STUB_DIR/ocir_password"
  touch "$STUB_DIR/apply_fails"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "ocir: apply failure fails" [ "$rc" -ne 0 ]
  check "ocir: temporary file removed after failure" [ ! -e "$(cat "$STUB_DIR/dockerconfig_path" 2>/dev/null || echo /nonexistent)" ]

  reset
  touch "$STUB_DIR/secret_fails"
  run_rendered "$tpl" >/dev/null 2>&1
  rc=$?
  check "ocir: vault failure fails" [ "$rc" -ne 0 ]
  check "ocir: vault failure creates no secret" no called "create secret"
}

# ---------------------------------------------------------------- module against the simulated CLIs
test_module() {
  local dir="$WORK/module" y=".terraform/oke-exec" rc
  mkdir -p "$dir/tests"
  cp -R "$ROOT/modules/extensions/." "$dir/"
  cp "$ROOT/tests/kube_exec/extensions.tftest.hcl" "$dir/tests/"
  reset
  echo synthetic-sa-token >"$STUB_DIR/token"
  terraform -chdir="$dir" init -input=false -no-color >/dev/null || { ko "module: init"; return; }
  TF_VAR_kube_exec_script="$SCRIPT" terraform -chdir="$dir" test -no-color >"$WORK/tftest.log" 2>&1
  rc=$?
  check "module: terraform test passes" [ "$rc" -eq 0 ]
  [ "$rc" -eq 0 ] || cat "$WORK/tftest.log"

  y="$y/$(printf '%s' ocid1.cluster.test | shasum -a 256 | cut -c1-16)/yaml"
  local server="kubectl apply --force-conflicts=true --server-side -f $y"
  check "cmd: argocd namespace" called "kubectl create ns argocd --dry-run=client"
  check "cmd: argocd" called "$server/argocd.yaml"
  check "cmd: cluster_autoscaler" called "kubectl apply -f $y/cluster_autoscaler.yaml"
  check "cmd: dcgm_exporter crds" called "$server/dcgm_exporter.crds.yaml"
  check "cmd: dcgm_exporter manifest" called "$server/dcgm_exporter.manifest.yaml"
  check "cmd: gatekeeper" called "$server/gatekeeper.yaml"
  check "cmd: karpenter" called "$server/karpenter.yaml"
  check "cmd: metrics_server" called "$server/metrics_server.manifest.yaml"
  check "cmd: mpi_operator" called "kubectl apply -f $y/mpi-operator.manifest.yaml"
  check "cmd: multus" called "kubectl apply -f $y/multus.manifest.yaml"
  check "cmd: prometheus crds" called "$server/prometheus.crds.yaml"
  check "cmd: prometheus manifest" called "$server/prometheus.manifest.yaml"
  check "cmd: rdma_cni_plugin" called "kubectl apply -f $y/rdma-cni-daemonset.yaml"
  check "cmd: sriov_cni_plugin" called "kubectl apply -f $y/sriov_cni_plugin-manifest.yaml"
  check "cmd: sriov_device_plugin" called "kubectl apply -f $y/sriov_device_plugin-manifest.yaml"
  check "cmd: whereabouts" called "kubectl apply -f $y/whereabouts.ippools.crd.yaml -f $y/whereabouts.overlap_res.crd.yaml -f $y/whereabouts.manifest.yaml"
  check "cmd: cilium crds" called "kubectl apply -n cilium-ns --force-conflicts=true --server-side -f $y/cilium.crds.yaml"
  check "cmd: cilium helm" called "helm upgrade --install cilium cilium --repo https://helm.cilium.io --version 1.16.3 --namespace cilium-ns --create-namespace --skip-crds -f $y/cilium.values-override.yaml"
  check "cmd: admin binding" called "kubectl apply -f $y/kube-admin-binding.yaml"
  check "cmd: no systemd-cat wrapper" no called "systemd-cat"

  local prom crds helm_line binding last
  prom=$(called_line "$server/prometheus.manifest.yaml")
  crds=$(called_line "cilium.crds.yaml")
  helm_line=$(called_line "helm upgrade")
  binding=$(called_line "kube-admin-binding.yaml")
  last=$(grep -nE 'kubectl (apply|create) ' "$STUB_DIR/calls" | grep -v 'dry-run' | tail -n 1 | cut -d: -f1)
  check "order: prometheus before cilium" [ "$prom" -lt "$crds" ]
  check "order: cilium crds before helm" [ "$crds" -lt "$helm_line" ]
  check "order: admin binding last" [ "$binding" -eq "$last" ]

  local token
  token=$(find "$dir/.terraform/oke-exec" -name 'sa-token-crb-sa-kube-system')
  check "module: token isolated by cluster hash" [ -n "$token" ]
}

test_binding_template() {
  local out="$WORK/binding" empty="$WORK/binding_empty"
  render "$ROOT/modules/extensions/templates/kube-admin-binding.yaml.tpl" "$out" '{user_ocids=["ocid1.user.a","ocid1.user.b"]}'
  render "$ROOT/modules/extensions/templates/kube-admin-binding.yaml.tpl" "$empty" '{user_ocids=[]}'
  check "binding: subjects listed" [ "$(grep -c 'kind: User' "$out")" -eq 2 ]
  check "binding: OCID present" grep -q 'name: "ocid1.user.b"' "$out"
  check "binding: empty list revokes" grep -q '^subjects: \[\]$' "$empty"
}

test_kube_exec
test_service_account
test_remove_addons
test_await_node
test_ocir
test_binding_template
if [ -z "$MODE" ]; then
  test_module
fi

echo "--- $checks checks, $failures failures (bash ${BASH_VERSION})"
[ "$failures" -eq 0 ]
