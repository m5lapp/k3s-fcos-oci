variable "compartment_id" {
  description = "OCI Compartment ID"
  type        = string
}

variable "rfc1918_cidr_block" {
  # https://www.rfc-editor.org/rfc/rfc1918
  description = "The RFC 1918 private IP address space to use for the VCN"
  type        = string
  default     = "10.0.0.0/24"
}

variable "tenancy_ocid" {
  description = "The tenancy OCID."
  type        = string
}

