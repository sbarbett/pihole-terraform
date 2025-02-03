###############################
# main.tf
###############################

terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.23.0"
    }
  }
}

provider "oci" {
  config_file_profile = "DEFAULT"
  region              = var.region
}

# Generate a unique suffix for resource names
resource "random_pet" "suffix" {
  length = 2
}

# Create a Virtual Cloud Network (VCN)
resource "oci_core_vcn" "pihole_vcn" {
  compartment_id = var.compartment_id
  display_name   = "pihole-vcn-${random_pet.suffix.id}"
  cidr_block     = "10.0.0.0/16"
}

# Create a Subnet in the VCN (regional subnet)
resource "oci_core_subnet" "pihole_subnet" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.pihole_vcn.id
  display_name   = "pihole-subnet-${random_pet.suffix.id}"
  cidr_block     = "10.0.1.0/24"
}

# Create an Internet Gateway
resource "oci_core_internet_gateway" "pihole_ig" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.pihole_vcn.id
  display_name   = "pihole-ig-${random_pet.suffix.id}"
  enabled        = true
}

# Update the Default Route Table for the VCN to point to the Internet Gateway
resource "oci_core_default_route_table" "pihole_default_rt" {
  manage_default_resource_id = oci_core_vcn.pihole_vcn.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.pihole_ig.id
  }
}

# Update the default security list to allow:
# - TCP port 22 for SSH
# - ICMP for diagnostics (e.g. ping)
# - UDP port 51820 for WireGuard
resource "oci_core_default_security_list" "pihole_default_sl" {
  manage_default_resource_id = oci_core_vcn.pihole_vcn.default_security_list_id

  ingress_security_rules {
    protocol = "6"   # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "1"   # ICMP (protocol 1)
    source   = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "17"  # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 51820
      max = 51820
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Create an OCI Compute Instance for Pi-hole
resource "oci_core_instance" "pihole_vm" {
  compartment_id      = var.compartment_id
  availability_domain = var.availability_domain
  shape               = "VM.Standard.E2.1.Micro"
  display_name        = "pihole-instance-${random_pet.suffix.id}"

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_ocid
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.pihole_subnet.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = file(var.public_key_path)
  }
}

# Provision the instance with your setup script using a null_resource.
resource "null_resource" "setup_pihole" {
  depends_on = [oci_core_instance.pihole_vm]

  # Copy the setup script to the remote instance.
  provisioner "file" {
    source      = "setup.sh"
    destination = "/home/ubuntu/setup.sh"

    connection {
      type        = "ssh"
      host        = oci_core_instance.pihole_vm.public_ip
      user        = "ubuntu"
      private_key = file(var.private_key_path)
    }
  }

  # Execute the setup script on the remote instance.
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/setup.sh",
      "sudo /home/ubuntu/setup.sh"
    ]
    connection {
      type        = "ssh"
      host        = oci_core_instance.pihole_vm.public_ip
      user        = "ubuntu"
      private_key = file(var.private_key_path)
    }
  }
}

# After successful provisioning, create a local .wireguard directory and copy the WireGuard config using sudo.
resource "null_resource" "copy_wireguard_config" {
  depends_on = [null_resource.setup_pihole]

  provisioner "local-exec" {
    command = "mkdir -p ~/.wireguard && ssh -i ${var.private_key_path} ubuntu@${oci_core_instance.pihole_vm.public_ip} \"sudo cat /home/ubuntu/pihole-stack/config/peer1/peer1.conf\" > ~/.wireguard/wg-pihole.conf"
  }
}

# Output the instance's public IP address.
output "instance_public_ip" {
  value = oci_core_instance.pihole_vm.public_ip
}

# Output the generated instance name
output "instance_name" {
  value = oci_core_instance.pihole_vm.display_name
}

# Output the generated VCN name
output "vcn_name" {
  value = oci_core_vcn.pihole_vcn.display_name
}