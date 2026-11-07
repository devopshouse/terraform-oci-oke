set -euo pipefail

# NotAuthorizedOrNotFound does not separate "already removed" from "no permission", so the installed list decides.
installed=$(oci --connection-timeout 10 --read-timeout 60 ce cluster list-addons \
  --cluster-id '${cluster_id}' --region '${region}' --all --query 'data[].name')

if ! printf '%s\n' "$installed" | grep -Fq '"${addon_name}"'; then
  echo "Addon ${addon_name} is not installed, nothing to remove"
  exit 0
fi

echo 'Removing ${addon_name} addon'
${disable_command} --region '${region}'
${custom_commands}
