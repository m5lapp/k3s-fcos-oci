variable "compartment_id" {
  description = "OCI Compartment ID"
  type        = string
}

variable "domain_name" {
  description = "Your domain name, this is used in setting up Node SANs"
  type        = string
  default     = "example.com"
}

variable "fingerprint" {
  description = "The fingerprint of the key to use for signing"
  type        = string
}

variable "private_key_path" {
  description = "The path to the private key to use for signing"
  type        = string
}

variable "region" {
  description = "The region to connect to. Default: uk-london-1"
  type        = string
  default     = "uk-london-1"
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

variable "tenancy_ocid" {
  description = "The tenancy OCID."
  type        = string
}

variable "user_ocid" {
  description = "The user OCID."
  type        = string
}

