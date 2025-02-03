##############################
# variables.tf
##############################

variable "compartment_id" {
  description = "The compartment OCID in which to create resources."
  type        = string
}

variable "region" {
  description = "OCI region, e.g. us-ashburn-1"
  type        = string
}

variable "availability_domain" {
  description = "OCI availability domain, e.g. Uocm:PHX-AD-1"
  type        = string
}

variable "ubuntu_image_ocid" {
  description = "OCID for the Ubuntu Minimal image"
  type        = string
}

variable "public_key_path" {
  description = "Path to the SSH public key to authorize on the instance"
  type        = string
}

variable "private_key_path" {
  description = "Path to the SSH private key used for connecting to the instance"
  type        = string
}
