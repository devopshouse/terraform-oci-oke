set -euo pipefail

sa_name='${sa_name}'
sa_namespace='${sa_namespace}'
secret_name='${secret_name}'
token_file='${token_file}'
token_wait_seconds="$${KUBE_EXEC_TOKEN_WAIT_SECONDS:-60}"
token_wait_interval="$${KUBE_EXEC_TOKEN_WAIT_INTERVAL:-5}"

fail() {
  echo "service-account-local: $*" >&2
  exit 1
}

# An existing binding is validated and never rewritten: it can belong to another manager.
check_binding() {
  local description=$1 expected_role=$2 actual
  shift 2
  actual=$(kubectl get "$@" -o go-template='{{.roleRef.kind}}/{{.roleRef.name}}{{"\n"}}{{range .subjects}}{{.kind}}/{{.namespace}}/{{.name}}{{"\n"}}{{end}}')
  [ "$(printf '%s\n' "$actual" | head -n 1)" = "$expected_role" ] \
    || fail "$description: roleRef differs from $expected_role."
  printf '%s\n' "$actual" | tail -n +2 | grep -Fxq "ServiceAccount/$sa_namespace/$sa_name" \
    || fail "$description: subject ServiceAccount $sa_namespace/$sa_name not found."
}

kubectl get namespace "$sa_namespace" >/dev/null 2>&1 || kubectl create namespace "$sa_namespace"
kubectl get serviceaccount -n "$sa_namespace" "$sa_name" >/dev/null 2>&1 \
  || kubectl create serviceaccount -n "$sa_namespace" "$sa_name"

%{ if cluster_role_binding != "none" ~}
if kubectl get clusterrolebinding '${cluster_role_binding}' >/dev/null 2>&1; then
  check_binding 'ClusterRoleBinding ${cluster_role_binding}' 'ClusterRole/${cluster_role}' clusterrolebinding '${cluster_role_binding}'
else
  kubectl create clusterrolebinding '${cluster_role_binding}' --clusterrole='${cluster_role}' --serviceaccount="$sa_namespace:$sa_name"
fi

%{ endif ~}
%{ if role_binding != "none" ~}
if kubectl get rolebinding -n "$sa_namespace" '${role_binding}' >/dev/null 2>&1; then
%{ if role != "" ~}
  check_binding 'RoleBinding ${role_binding}' 'Role/${role}' rolebinding -n "$sa_namespace" '${role_binding}'
else
  kubectl create rolebinding -n "$sa_namespace" '${role_binding}' --role='${role}' --serviceaccount="$sa_namespace:$sa_name"
%{ else ~}
  check_binding 'RoleBinding ${role_binding}' 'ClusterRole/${cluster_role}' rolebinding -n "$sa_namespace" '${role_binding}'
else
  kubectl create rolebinding -n "$sa_namespace" '${role_binding}' --clusterrole='${cluster_role}' --serviceaccount="$sa_namespace:$sa_name"
%{ endif ~}
fi

%{ endif ~}
if kubectl get secret -n "$sa_namespace" "$secret_name" >/dev/null 2>&1; then
  secret_type=$(kubectl get secret -n "$sa_namespace" "$secret_name" -o go-template='{{.type}}')
  secret_sa=$(kubectl get secret -n "$sa_namespace" "$secret_name" \
    -o go-template='{{with .metadata.annotations}}{{index . "kubernetes.io/service-account.name"}}{{end}}')
  [ "$secret_type" = "kubernetes.io/service-account-token" ] || fail "Secret $secret_name has type $secret_type."
  [ "$secret_sa" = "$sa_name" ] || fail "Secret $secret_name is annotated for service account '$secret_sa'."
else
  kubectl create -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $secret_name
  namespace: $sa_namespace
  annotations:
    kubernetes.io/service-account.name: $sa_name
type: kubernetes.io/service-account-token
EOF
fi

# The token controller fills the Secret asynchronously.
deadline=$((SECONDS + token_wait_seconds))
while true; do
  token=$(kubectl get secret -n "$sa_namespace" "$secret_name" \
    -o go-template='{{with .data}}{{with .token}}{{. | base64decode}}{{end}}{{end}}')
  [ -n "$token" ] && break
  [ "$SECONDS" -lt "$deadline" ] || fail "Secret $secret_name has no token after $${token_wait_seconds}s."
  sleep "$token_wait_interval"
done

# The final path only ever holds a complete token.
umask 077
token_dir=$(dirname "$token_file")
mkdir -p "$token_dir"
token_tmp=$(mktemp "$token_dir/.sa-token.XXXXXX")
trap 'rm -f "$token_tmp"' EXIT
printf '%s\n' "$token" >"$token_tmp"
mv "$token_tmp" "$token_file"
