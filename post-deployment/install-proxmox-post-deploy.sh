#!/bin/bash -ex
#
# install-proxmox-post-deploy.sh - Install Proxmox VE after MAAS deployment
#
# This script should be run AFTER MAAS has deployed the system and
# properly configured hostname and networking.
#
# Usage:
#   ssh debian@<deployed-host> 'bash -s' < install-proxmox-post-deploy.sh
#   OR
#   Copy this script to the deployed host and run: sudo bash install-proxmox-post-deploy.sh
#
# Based on: https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie

export DEBIAN_FRONTEND=noninteractive

echo "Installing Proxmox VE 9.1 on deployed Debian 13 system..."

# Verify hostname is properly configured (not localhost or 127.0.0.1)
HOSTNAME=$(hostname -f)
HOSTNAME_IP=$(hostname -I | awk '{print $1}')

if [ "$HOSTNAME" = "localhost" ] || [ -z "$HOSTNAME_IP" ]; then
    echo "ERROR: Hostname is not properly configured!"
    echo "Current hostname: $HOSTNAME"
    echo "Current IP: $HOSTNAME_IP"
    echo "Please ensure /etc/hosts has an entry mapping the hostname to a real IP address"
    exit 1
fi

echo "Hostname check passed: $HOSTNAME resolves to $HOSTNAME_IP"

# Update package lists
echo "Updating package lists..."
apt-get update

# Full system upgrade
echo "Performing full system upgrade..."
apt-get -y full-upgrade

# Install Proxmox kernel
echo "Installing Proxmox kernel..."
apt-get install -y proxmox-default-kernel

# Reboot to Proxmox kernel
echo "Rebooting to Proxmox kernel..."
echo "After reboot, run this script again to complete installation"
read -p "Press Enter to reboot now, or Ctrl+C to cancel..."
reboot
