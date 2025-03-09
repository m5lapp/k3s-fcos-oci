resource "oci_core_instance" "server_0" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domain.ad_2.name
  display_name        = "k3s-server-0"
  shape               = local.server_instance_config.shape_id

  source_details {
    source_id   = local.server_instance_config.source_id
    source_type = local.server_instance_config.source_type
  }

  shape_config {
    memory_in_gbs = local.server_instance_config.ram
    ocpus         = local.server_instance_config.ocpus
  }

  create_vnic_details {
    subnet_id  = var.cluster_subnet_id
    private_ip = local.server_instance_config.server_ip_0
    nsg_ids = [
      var.permit_http_nsg_id,
      var.permit_kubectl_nsg_id,
      var.permit_ssh_nsg_id
    ]
  }

  metadata = {
    "ssh_authorized_keys" = local.server_instance_config.metadata.ssh_authorized_keys
    "user_data"           = local.user_data_script
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_instance" "server_1" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domain.ad_2.name
  display_name        = "k3s-server-1"
  depends_on          = [oci_core_instance.server_0]
  shape               = local.server_instance_config.shape_id

  source_details {
    source_id   = local.server_instance_config.source_id
    source_type = local.server_instance_config.source_type
  }

  shape_config {
    memory_in_gbs = local.server_instance_config.ram
    ocpus         = local.server_instance_config.ocpus
  }

  create_vnic_details {
    subnet_id  = var.cluster_subnet_id
    private_ip = local.server_instance_config.server_ip_1
    nsg_ids = [
      var.permit_http_nsg_id,
      var.permit_kubectl_nsg_id,
      var.permit_ssh_nsg_id
    ]
  }

  metadata = {
    "ssh_authorized_keys" = local.server_instance_config.metadata.ssh_authorized_keys
    "user_data"           = local.user_data_script
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_instance" "agent" {
  count          = local.agent_instance_config.count
  compartment_id = var.compartment_id
  # Instances using the VM.Standard.E2.1.Micro shape MUST go in the
  # DhmS:UK-LONDON-1-AD-2 availability domain, so this must be hard-coded.
  availability_domain = data.oci_identity_availability_domain.ad_2.name
  display_name        = "k3s-agent-${count.index}"
  depends_on          = [oci_core_instance.server_1]
  shape               = local.agent_instance_config.shape_id

  source_details {
    source_id   = local.agent_instance_config.source_id
    source_type = local.agent_instance_config.source_type
  }

  shape_config {
    memory_in_gbs = local.agent_instance_config.ram
    ocpus         = local.agent_instance_config.ocpus
  }

  create_vnic_details {
    subnet_id  = var.cluster_subnet_id
    private_ip = cidrhost(var.rfc1918_cidr_block, 20 + count.index)
    nsg_ids = [
      var.permit_http_nsg_id,
      var.permit_ssh_nsg_id
    ]
  }

  metadata = {
    "ssh_authorized_keys" = local.agent_instance_config.metadata.ssh_authorized_keys
    "user_data"           = local.user_data_script
  }
}

