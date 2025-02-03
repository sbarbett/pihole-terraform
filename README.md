# pihole-terraform

This Terraform module provisions an Oracle Cloud Infrastructure (OCI) Virtual Machine along with the necessary networking components to run Pi-hole, Unbound, and WireGuard. The result is a portable VPN that routes your traffic through a secure connection while blocking ads and trackers with Pi-hole.

## Prerequisites

- **Terraform:**  
  [Download and install Terraform](https://www.terraform.io/downloads.html) (version 0.12 or later is recommended).

- **OCI Account:**  
  An OCI account with the appropriate permissions and a properly configured `~/.oci/config` file (or environment variables).

- **SSH Key Pair:**  
  You must have an SSH key pair (e.g., `ubuntu-pihole.key` and `ubuntu-pihole.key.pub`) for accessing the instance. This key pair will be used for the instance’s SSH access and by the module’s provisioners.

## Usage

1. **Clone or Download the Module:**

   ```bash
   git clone https://github.com/sbarbett/pihole-terraform.git
   cd pihole-terraform
   ```

2. **Configure Variables:**
   Create a file named `terraform.tfvars` in the module’s root directory with your environment-specific values. For example:

   ```bash
   region               = "us-ashburn-1"
   compartment_id       = "ocid1.tenancy.oc1..uniqueID"
   availability_domain  = "uPHd:US-ASHBURN-AD-2"
   ubuntu_image_ocid    = "ocid1.image.oc1.iad.aaaaaaaa3ye6a7m4sf5kvpqp2n5qwuorjnomdsdwv2udi74owkpveaepw7lq"
   public_key_path      = "~/.ssh/ubuntu-pihole.key.pub"
   private_key_path     = "~/.ssh/ubuntu-pihole.key"
   ```

   Adjust the values to match your OCI tenancy, region, and credentials.

3. **Initialize Terraform:**

   ```bash
   terraform init
   ```

4. **Review the Execution Plan:**

   ```bash
   terraform plan
   ```

5. **Apply the Configuration:**

   ```bash
   terraform apply
   ```

   When prompted, type `yes` to confirm. Terraform will create all the resources, run the setup script on the instance, and automatically copy the WireGuard configuration to your local machine.

6. **Verify:**

   * **SSH Access:** You should be able to SSH into the instance using your SSH key.
      - From here you can navigate to the `pihole-stack` directory and use `docker compose logs -f` to see your services running.
   * **WireGuard Config:** Check that the file `~/.wireguard/wg-pihole.conf` exists on your local machine.
      - You should be able to connect to the VPN using a WireGuard client of your choosing. For example:

         ```bash
         wg-quick up ~/.wireguard/wg-pihole.conf
         ```

   * **Pi-Hole Interface:** Once connected to the client, pull up the Pi-hole interface in your browser by navigating to http://192.168.5.2/

### Deprovisioning Resources

To clean up and remove all resources provisioned by this module, run:

```bash
terraform destroy
```

# License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.