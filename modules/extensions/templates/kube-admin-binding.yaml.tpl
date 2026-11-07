apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kube-exec-admin-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
%{ if length(user_ocids) == 0 ~}
subjects: []
%{ else ~}
subjects:
%{ for ocid in user_ocids ~}
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: "${ocid}"
%{ endfor ~}
%{ endif ~}
