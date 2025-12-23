#!/bin/bash -ex
#
# install-proxmox.sh - Install Proxmox VE 9.1 on Debian 13 Trixie
#
# Based on: https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie
#
# Copyright (C) 2025
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

export DEBIAN_FRONTEND=noninteractive

packer_apt_proxy_config="/etc/apt/apt.conf.d/packer-proxy.conf"
if [ ! -z "${APT_PROXY:-}" ]; then
    echo "Acquire::http::Proxy \"${APT_PROXY}\";" > $packer_apt_proxy_config
fi
if [ ! -z "${APT_PROXY_HTTPS:-}" ]; then
    echo "Acquire::https::Proxy \"${APT_PROXY_HTTPS}\";" >> $packer_apt_proxy_config
fi

echo "Installing Proxmox VE 9.1 on Debian Trixie..."

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
echo "b4e8c6238b8ff42c2fa84c1611b396d7f42d2e1f  /usr/share/keyrings/proxmox-archive-keyring.gpg" | sha1sum -c -

# Update package lists
echo "Updating package lists..."
apt-get update

# Full system upgrade
echo "Performing full system upgrade..."
apt-get -y full-upgrade

# Install Proxmox kernel first
echo "Installing Proxmox kernel..."
apt-get install -y proxmox-default-kernel

# Install Proxmox VE and required packages
echo "Installing Proxmox VE..."
# Preconfigure postfix to avoid interactive prompts
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
echo "postfix postfix/mailname string localhost" | debconf-set-selections

apt-get install -y \
    proxmox-ve \
    postfix \
    open-iscsi \
    chrony

# Remove standard Debian kernel in favor of Proxmox kernel
echo "Removing standard Debian kernel..."
apt-get remove -y linux-image-amd64 'linux-image-6.12*' || true

# Remove os-prober (not needed for hypervisor)
echo "Removing os-prober..."
apt-get remove -y os-prober || true

# Clean up
echo "Cleaning up..."
apt-get autoremove -y
apt-get clean

echo "Proxmox VE installation complete!"
echo "Installed packages:"
dpkg -l | grep -E "pve-|proxmox-"
