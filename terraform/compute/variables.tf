variable "cluster_subnet_id" {
  description = "Subnet for the bastion instance"
  type        = string
}

variable "compartment_id" {
  description = "OCI Compartment ID"
  type        = string
}

variable "domain_name" {
  description = "Your domain name, this is used in setting up Node SANs"
  type        = string
  default     = "example.com"
}

variable "init_agent_image" {
  description = "The OCID for the x86_64 agent image for the initial installation, must match the configured region"
  type        = string
  # https://docs.oracle.com/iaas/images/oracle-linux-9x/oracle-linux-9-4-minimal-2024-09-30-0.htm
  # Oracle-Linux-9.4-Minimal-2024.09.30-0
  default = "ocid1.image.oc1.uk-london-1.aaaaaaaal5x4avnng54idrnesph7bpfy5dhtaazt6cod52wiwlcbo5vbelsq"
}

variable "init_server_image" {
  description = "The OCID for the aarch64 server image for the initial installation, must match the configured region"
  type        = string
  # https://docs.oracle.com/en-us/iaas/images/oracle-linux-9x/oracle-linux-9-4-aarch64-2024-11-30-0.htm
  # Oracle-Linux-9.4-aarch64-2024.11.30-0
  default = "ocid1.image.oc1.uk-london-1.aaaaaaaaddsnxqcnjih3csusa2ixtq3wbhl3qdonmhbdtm7lffiindovy2kq"
}

variable "permit_http_nsg_id" {
  description = "NSG to permit HTTP(S)"
  type        = string
}

variable "permit_kubectl_nsg_id" {
  description = "NSG to permit Kubectl"
  type        = string
}

variable "permit_ssh_nsg_id" {
  description = "NSG to permit SSH"
  type        = string
}

variable "rfc1918_cidr_block" {
  # https://www.rfc-editor.org/rfc/rfc1918
  description = "The RFC 1918 private IP address space to use for the VCN"
  type        = string
  default     = "10.0.0.0/24"
}

variable "ssh_authorized_keys" {
  description = "List of authorized SSH keys"
  type        = list(string)
}

variable "taint_low_resource_nodes" {
  description = "Apply a taint to Nodes with low resources so that only Pods with specific tolerations can be scheduled on them"
  type        = bool
  default     = true
}

variable "tenancy_ocid" {
  description = "The tenancy OCID."
  type        = string
}

locals {
  server_instance_config = {
    shape_id    = "VM.Standard.A1.Flex"
    ocpus       = 2
    ram         = 12
    source_id   = "${var.init_server_image}"
    source_type = "image"
    server_ip_0 = cidrhost(var.rfc1918_cidr_block, 10)
    server_ip_1 = cidrhost(var.rfc1918_cidr_block, 11)
    metadata = {
      "ssh_authorized_keys" = join("\n", var.ssh_authorized_keys)
    }
  }

  agent_instance_config = {
    shape_id    = "VM.Standard.E2.1.Micro"
    count       = 2
    ocpus       = 1
    ram         = 1
    source_id   = "${var.init_agent_image}"
    source_type = "image"
    ip_offset   = 20
    metadata = {
      "ssh_authorized_keys" = join("\n", var.ssh_authorized_keys)
    }
  }

  # Common values that apply to every Node in the cluster. These will be merged
  # with the Node-specific values when rendering the template for each one.
  butane_file_common_values = tomap({
    cluster_token     = random_string.cluster_token.result,
    domain_name       = var.domain_name,
    primary_server_ip = local.server_instance_config.server_ip_0,
    # Values in a map must all be of the same type, so we need to convert the
    # list of SSH keys to a comma-separated string and split it in the template.
    ssh_authorized_keys      = join(",", var.ssh_authorized_keys),
    taint_low_resource_nodes = var.taint_low_resource_nodes,
  })

  # butane_file_map builds a base64 encoded string of a JSON object that maps
  # the name of a Butane file to the base64 encoded contents for each Node in
  # the cluster.
  butane_file_map = base64encode(
    jsonencode(
      merge(
        tomap({
          "k3s-server-0.bu" = base64encode(
            templatefile(
              "${path.module}/templates/fcos.bu",
              merge(
                local.butane_file_common_values,
                {
                  ip_address       = local.server_instance_config.server_ip_0,
                  node_index       = "0",
                  node_type        = "server",
                  rollout_time     = "23:00"
                  rollout_wariness = 0.9,
                }
              )
            )
          ),
          "k3s-server-1.bu" = base64encode(
            templatefile(
              "${path.module}/templates/fcos.bu",
              merge(
                local.butane_file_common_values,
                {
                  ip_address       = local.server_instance_config.server_ip_1,
                  node_index       = "1",
                  node_type        = "server",
                  rollout_time     = "21:00"
                  rollout_wariness = 0.8,
                }
              )
            )
          )
        }),
        {
          for i in range(local.agent_instance_config.count) : "k3s-agent-${i}.bu" =>
          base64encode(
            templatefile(
              "${path.module}/templates/fcos.bu",
              merge(
                local.butane_file_common_values,
                {
                  ip_address       = cidrhost(var.rfc1918_cidr_block, local.agent_instance_config.ip_offset + i)
                  node_index       = "${i}",
                  node_type        = "agent",
                  rollout_time     = "0${1 + 2 * i}:00"
                  rollout_wariness = 0.1 + 0.1 * i,
                }
              )
            )
          )
        }
      )
    )
  )

  # user_data_script is the script that runs on each instance the first time it
  # is booted up. We use it here to write the Butane file for each Node and then
  # convert them into Ignition files used to install Fedora CoreOS.
  user_data_script = base64encode(
    templatefile(
      "${path.module}/templates/user_data_script.sh",
      { butane_file_map = local.butane_file_map }
    )
  )
}

