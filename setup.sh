#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# Automated Pi-hole + Unbound + WireGuard setup script
# -----------------------------------------------------------------------------
# This script will:
#  1. Update the system and install prerequisites.
#  2. Install Docker and Docker Compose.
#  3. Disable systemd-resolved and configure a static resolv.conf.
#  4. Create a Docker Compose stack for Pi-hole, Unbound, and WireGuard.
#  5. Start the containers.
#
# If not using Terraform, Some manual steps are still required (for example, 
# creating your Oracle Cloud instance and configuring your SSH keys). This 
# script assumes you are logged in on your VM.
#
# Run as root (or via sudo). If running with sudo, the non-root user’s home
# directory will be used for the Pi-hole stack.
# -----------------------------------------------------------------------------

# Make sure the script is run as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root. Please run with sudo."
  exit 1
fi

# Determine the non-root user (if any) so we place files in their home.
if [ -n "$SUDO_USER" ]; then
  USER_NAME="$SUDO_USER"
  USER_HOME=$(eval echo "~$SUDO_USER")
else
  USER_NAME=$(whoami)
  USER_HOME="$HOME"
fi

echo "Running setup as user: $USER_NAME (home directory: $USER_HOME)"
echo "--------------------------------------------------------------"

# 1. Update the system
echo "Updating system packages..."
apt update && apt full-upgrade -y

# 2. Install prerequisites
echo "Installing prerequisites..."
apt-get install -y ca-certificates curl gnupg lsb-release

# 3. Set up Docker’s official GPG key and repository
echo "Setting up Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker apt repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update

# 4. Install Docker and Docker Compose plugin
echo "Installing Docker packages..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Enable Docker to start on boot
echo "Enabling Docker services..."
systemctl enable docker.service
systemctl enable containerd.service

# 6. Add the non-root user to the Docker group
echo "Adding user $USER_NAME to the Docker group..."
usermod -aG docker "$USER_NAME"
echo "NOTE: You may need to log out and log back in for the Docker group changes to take effect."

# 7. Disable systemd-resolved and set a static nameserver
echo "Disabling systemd-resolved..."
systemctl disable --now systemd-resolved || true
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# Restart Docker in case it was using systemd-resolved
echo "Restarting Docker..."
systemctl restart docker

# 8. Set up the Docker environment for Pi-hole, Unbound, and WireGuard
PIHOLE_STACK_DIR="$USER_HOME/pihole-stack"
echo "Creating Pi-hole stack directory at: $PIHOLE_STACK_DIR"
mkdir -p "$PIHOLE_STACK_DIR"

cd "$PIHOLE_STACK_DIR"

# Create blank configuration files for Unbound
echo "Creating blank Unbound config files..."
mkdir -p ./etc-unbound
touch ./etc-unbound/a-records.conf ./etc-unbound/srv-records.conf ./etc-unbound/forward-records.conf

# Create directories for Pi-hole persistence (if not already present)
mkdir -p ./etc-pihole ./etc-dnsmasq.d

# Create the docker-compose.yml file
echo "Creating docker-compose.yml file..."
cat > docker-compose.yml << 'EOF'
networks:
  dns_net:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.5.0/24  # Custom subnet for the Docker network

services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80/tcp"  # Pi-hole Web UI
    environment:
      WEBPASSWORD: 'SOMETHING' # Change this to your desired password
      DNS1: '192.168.5.3'      # Unbound's static IP
      DNS2: '192.168.5.3'
      DNSMASQ_LISTENING: 'all'
      FTLCONF_LOCAL_IPV4: '192.168.5.2'  # Pi-hole's static IP
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    restart: unless-stopped
    depends_on:
      - unbound
    networks:
      dns_net:
        ipv4_address: 192.168.5.2  # Static IP for Pi-hole

  unbound:
    container_name: unbound
    image: pedantic/unbound:latest
    volumes:
      - './etc-unbound:/opt/unbound/etc/unbound'
    restart: unless-stopped
    networks:
      dns_net:
        ipv4_address: 192.168.5.3  # Static IP for Unbound

  wireguard:
    container_name: wireguard
    image: linuxserver/wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      PUID: 1000
      PGID: 1000
      TZ: Etc/UTC
      SERVERPORT: 51820
      PEERS: 1
      PEERDNS: 192.168.5.2  # Pi-hole as DNS resolver
      INTERNAL_SUBNET: 10.6.0.0/24
    volumes:
      - './config:/config'
      - '/lib/modules:/lib/modules'
    ports:
      - "51820:51820/udp"
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    restart: unless-stopped
    depends_on:
      - pihole
    networks:
      dns_net:
        ipv4_address: 192.168.5.4
EOF

# 9. Start the Docker Compose stack
echo "Starting Docker containers (this may take a moment)..."
docker compose up -d

# 10. (Optional) Install dnsutils for testing DNS resolution
echo "Installing dnsutils for DNS testing..."
apt-get install -y dnsutils

echo "--------------------------------------------------------------"
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  • Test DNS resolution locally with: dig @127.0.0.1 www.google.com"
echo "  • To view container logs, run: docker compose logs -f"
echo "  • The WireGuard client configuration will be generated at: $PIHOLE_STACK_DIR/config/peer1/peer1.conf"
echo "  • Remember that the Pi-hole web UI is at http://192.168.5.2 but is accessible only via the WireGuard VPN."
echo ""
echo "If you just added your user ($USER_NAME) to the Docker group, please log out and back in to use Docker without sudo."
echo "--------------------------------------------------------------"
