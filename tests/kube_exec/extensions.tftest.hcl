# Runs the module with real null, local and external providers against the simulated CLIs from run.sh.

mock_provider "helm" {
  mock_data "helm_template" {
    defaults = {
      manifest = "kind: Manifest"
      crds     = ["kind: CustomResourceDefinition"]
      values   = ["key: value"]
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = "kind: Downloaded"
    }
  }
}

variables {
  region                     = "sa-saopaulo-1"
  state_id                   = "abcdef"
  worker_pools               = { pool = { autoscale = true, id = "ocid1.pool", size = 1 } }
  kubernetes_version         = "v1.34.2"
  expected_node_count        = 1
  cluster_private_endpoint   = "10.0.0.1"
  cluster_compartment_id     = "ocid1.compartment"
  vcn_compartment_id         = "ocid1.compartment"
  cluster_id                 = "ocid1.cluster.test"
  kube_exec_local            = true
  kube_exec_kube_endpoint    = "PRIVATE_ENDPOINT"
  kube_exec_admin_user_ocids = ["ocid1.user.b", "ocid1.user.a"]

  bastion_host      = null
  bastion_user      = "opc"
  operator_host     = "10.0.0.2"
  operator_user     = "opc"
  ssh_private_key   = "synthetic"
  bastion_is_public = "false"
  use_bastion       = false

  vcn_cidrs = ["10.0.0.0/16"]
  cni_type  = "flannel"
  pods_cidr = "10.244.0.0/16"

  cilium_install           = true
  cilium_reapply           = false
  cilium_namespace         = "cilium-ns"
  cilium_helm_version      = "1.16.3"
  cilium_helm_values       = {}
  cilium_helm_values_files = []

  multus_install       = true
  multus_namespace     = "default"
  multus_daemonset_url = null
  multus_version       = "3.9.3"

  sriov_device_plugin_install       = true
  sriov_device_plugin_namespace     = "kube-system"
  sriov_device_plugin_daemonset_url = null
  sriov_device_plugin_version       = "master"

  sriov_cni_plugin_install       = true
  sriov_cni_plugin_namespace     = "kube-system"
  sriov_cni_plugin_daemonset_url = null
  sriov_cni_plugin_version       = "master"

  rdma_cni_plugin_install       = true
  rdma_cni_plugin_namespace     = "kube-system"
  rdma_cni_plugin_daemonset_url = null
  rdma_cni_plugin_version       = "master"

  whereabouts_install       = true
  whereabouts_namespace     = "default"
  whereabouts_daemonset_url = null
  whereabouts_version       = "master"

  metrics_server_install           = true
  metrics_server_namespace         = "metrics"
  metrics_server_helm_version      = "3.12.2"
  metrics_server_helm_values       = {}
  metrics_server_helm_values_files = []

  cluster_autoscaler_install           = true
  cluster_autoscaler_namespace         = "kube-system"
  cluster_autoscaler_helm_version      = "9.43.2"
  cluster_autoscaler_helm_values       = {}
  cluster_autoscaler_helm_values_files = []
  expected_autoscale_worker_pools      = 1

  prometheus_install           = true
  prometheus_reapply           = false
  prometheus_namespace         = "metrics"
  prometheus_helm_version      = "45.2.0"
  prometheus_helm_values       = {}
  prometheus_helm_values_files = []

  dcgm_exporter_install           = true
  dcgm_exporter_reapply           = false
  dcgm_exporter_namespace         = "metrics"
  dcgm_exporter_helm_version      = "3.1.5"
  dcgm_exporter_helm_values       = {}
  dcgm_exporter_helm_values_files = []

  mpi_operator_install        = true
  mpi_operator_namespace      = "default"
  mpi_operator_deployment_url = null
  mpi_operator_version        = "0.4.0"

  gatekeeper_install           = true
  gatekeeper_namespace         = "kube-system"
  gatekeeper_helm_version      = "3.11.0"
  gatekeeper_helm_values       = {}
  gatekeeper_helm_values_files = []

  create_service_account = true
  service_accounts = {
    crb = {
      sa_name                 = "crb-sa"
      sa_namespace            = "kube-system"
      sa_cluster_role         = "cluster-admin"
      sa_cluster_role_binding = "crb-sa-crb"
    }
  }

  argocd_install           = true
  argocd_namespace         = "argocd"
  argocd_helm_version      = "7.7.0"
  argocd_helm_values       = {}
  argocd_helm_values_files = []

  karpenter_install           = true
  karpenter_namespace         = "karpenter"
  karpenter_version           = "1.0.0"
  karpenter_helm_values       = {}
  karpenter_helm_values_files = []
}

run "zero_nodes_suppress_node_dependent_extensions" {
  command = plan

  variables {
    expected_node_count             = 0
    expected_autoscale_worker_pools = 0
  }

  assert {
    condition     = !contains(keys(null_resource.kube_exec_apply), "metrics_server") && !contains(keys(local_sensitive_file.kube_exec_manifest), "metrics_server")
    error_message = "metrics_server must not generate a file or resource with zero nodes."
  }

  assert {
    condition     = !contains(keys(null_resource.kube_exec_apply), "cluster_autoscaler") && !contains(keys(local_sensitive_file.kube_exec_manifest), "cluster_autoscaler")
    error_message = "cluster_autoscaler must not generate a file or resource with zero nodes."
  }
}

run "zero_autoscaling_pools_suppress_autoscaler" {
  command = plan

  variables {
    expected_autoscale_worker_pools = 0
  }

  assert {
    condition     = !contains(keys(null_resource.kube_exec_apply), "cluster_autoscaler") && !contains(keys(local_sensitive_file.kube_exec_manifest), "cluster_autoscaler")
    error_message = "cluster_autoscaler must not generate a file or resource with zero autoscaling pools."
  }

  assert {
    condition     = contains(keys(null_resource.kube_exec_apply), "metrics_server")
    error_message = "metrics_server must stay enabled with nodes."
  }
}

run "service_account_disabled_creates_nothing" {
  command = plan

  variables {
    create_service_account = false
    service_accounts = {
      kubeconfigsa = {
        sa_name                 = "kubeconfigsa"
        sa_namespace            = "kube-system"
        sa_cluster_role         = "cluster-admin"
        sa_cluster_role_binding = "kubeconfigsa-crb"
      }
    }
  }

  assert {
    condition     = length(null_resource.service_account_local) == 0 && length(data.external.service_account_token_crb) == 0
    error_message = "create_service_account = false must not create or read a service account."
  }
}

run "remote_mode_keeps_operator_resources" {
  command = plan

  variables {
    kube_exec_local = false
  }

  assert {
    condition     = length(null_resource.metrics_server) == 1 && length(null_resource.service_account_crb) == 1
    error_message = "Remote mode must keep the operator resources."
  }

  assert {
    condition = alltrue([
      length(null_resource.kube_exec_apply) == 0,
      length(local_sensitive_file.kube_exec_manifest) == 0,
      length(null_resource.service_account_local) == 0,
      length(null_resource.kube_exec_admin_binding) == 0,
    ])
    error_message = "Remote mode must not create local resources."
  }
}

run "local_mode_applies_everything_through_the_script" {
  command = apply

  assert {
    condition = alltrue([
      length(null_resource.metrics_server) == 0,
      length(null_resource.service_account_crb) == 0,
      length(null_resource.service_account_token_retrieve_crb) == 0,
    ])
    error_message = "Local mode must not create operator resources."
  }

  assert {
    condition     = length(null_resource.kube_exec_apply) == 12
    error_message = "12 extensions without a defined order must have a kube_exec_apply instance."
  }

  assert {
    condition     = output.service_account_tokens["crb"] == "synthetic-sa-token"
    error_message = "The token written by the template must reach service_account_tokens."
  }
}
