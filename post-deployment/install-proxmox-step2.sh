#!/bin/bash -ex
#
# install-proxmox-step2.sh - Complete Proxmox VE installation (run after kernel reboot)
#
# This is step 2, run after rebooting into the Proxmox kernel

export DEBIAN_FRONTEND=noninteractive

# Verify we're running Proxmox kernel
KERNEL=$(uname -r)
if [[ ! "$KERNEL" =~ "pve" ]]; then
    echo "WARNING: Not running Proxmox kernel (current: $KERNEL)"
    echo "You should reboot into the Proxmox kernel first"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Installing Proxmox VE packages..."

# Preconfigure postfix to avoid interactive prompts
HOSTNAME=$(hostname -f)
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
echo "postfix postfix/mailname string $HOSTNAME" | debconf-set-selections

# Install Proxmox VE and required packages
apt-get install -y \
    proxmox-ve \
    postfix \
    open-iscsi \
    chrony

# Remove standard Debian kernel
echo "Removing standard Debian kernel..."
apt-get remove -y linux-image-amd64 'linux-image-6.12*' || true

# Remove os-prober (not needed for hypervisor)
echo "Removing os-prober..."
apt-get remove -y os-prober || true

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

echo ""
echo "=========================================="
echo "Proxmox VE installation complete!"
echo "=========================================="
echo ""
echo "Web interface: https://$(hostname -I | awk '{print $1}'):8006"
echo "Default login: root"
echo ""
echo "Note: You may see a subscription warning - this is normal for"
echo "installations using the 'pve-no-subscription' repository"
echo ""
