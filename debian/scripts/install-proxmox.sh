#!/bin/bash -ex
#
# install-proxmox.sh - Prepare system for Proxmox VE 9.1 installation
#
# This script ONLY configures the Proxmox repository.
# Actual Proxmox VE installation happens POST-deployment via MAAS
# when hostname and network are properly configured.
#
# Based on: https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
#
# Copyright (C) 2025
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# Only run if INSTALL_PROXMOX is set to "true"
if [ "${INSTALL_PROXMOX}" != "true" ]; then
    echo "Skipping Proxmox repository setup (INSTALL_PROXMOX != true)"
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

echo "Configuring Proxmox VE repository for post-deployment installation..."

# Add Proxmox VE repository in deb822 format
echo "Adding Proxmox VE repository..."
cat > /etc/apt/sources.list.d/pve-install-repo.sources << 'EOL'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOL

# Download and install Proxmox GPG key
echo "Downloading Proxmox archive keyring..."
wget https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
  -O /usr/share/keyrings/proxmox-archive-keyring.gpg

# Verify the keyring (expected hash for Trixie keyring)
echo "Verifying keyring..."
echo "08a2dc8925cd7120582ffb2f93f468744743361f  /usr/share/keyrings/proxmox-archive-keyring.gpg" | sha1sum -c -

# Update package lists to include Proxmox packages
echo "Updating package lists..."
apt-get update

echo "Proxmox repository configured successfully!"
echo "Proxmox VE can now be installed post-deployment with:"
echo "  apt-get install -y proxmox-ve postfix open-iscsi chrony"
