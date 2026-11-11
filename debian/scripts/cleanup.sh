#!/bin/bash -ex
#
# cleanup.sh - Clean up what we did to be able to build the image.
#
# Copyright (C) 2023 Canonical
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Everything in /run/packer_backup should be restored.
find /run/packer_backup
cp --preserve -r /run/packer_backup/ /
rm -rf /run/packer_backup

# We had to allow root to ssh for the image setup. Let's try to revert that.
sed -i s/^root:[^:]*/root:*/ /etc/shadow
rm -r /root/.ssh
rm -r /etc/ssh/ssh_host_*

# The packer_backup restore above can't be trusted for sshd: /run is a tmpfs
# and the bootcmd that fills it runs on every boot, so after the mid-build
# reboot the "backup" is the already-modified file. Revert the build-time SSH
# settings explicitly:
# - user-data's runcmd set "PermitRootLogin yes" in sshd_config
# - ssh_pwauth: True made cloud-init write sshd_config.d/50-cloud-init.conf
#   with "PasswordAuthentication yes"
sed -i -e 's/^PermitRootLogin yes$/#PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf
# Key-only SSH on the deployed host. Root keeps key login (Proxmox clustering
# needs it). Setting a root password for the web UI (PAM realm, port 8006)
# does not open password SSH. sshd uses the first value it reads, and
# sshd_config.d is included at the top of sshd_config, so this file wins.
cat > /etc/ssh/sshd_config.d/00-maas-proxmox.conf <<'EOF'
# Installed by MAAS-Proxmox image build. Remove to change SSH auth policy.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
chmod 644 /etc/ssh/sshd_config.d/00-maas-proxmox.conf

# Build leftovers in root's home
rm -rf /root/.ansible /root/.wget-hsts

# Proxmox cluster filesystem (pmxcfs) database from the build VM. It holds
# secrets that every deployed host would otherwise share: the build host's
# root SSH key in /etc/pve/priv/authorized_keys (root@packer-debian), the
# cluster CA key (pve-root-ca.key), the API ticket signing key (authkey.key),
# the CSRF key (pve-www.key) and the packer-debian node certificate.
# Delete it so first boot starts with an empty database; pveproxy's
# ExecStartPre (pvecm updatecerts) then generates fresh, per-host keys and
# certificates, as on a normal Proxmox install. root's authorized_keys ends
# up with only the key MAAS supplies plus the host's own new root key
# (Proxmox needs that one for clustering).
for svc in pve-ha-lrm pve-ha-crm pvescheduler pvestatd pveproxy pvedaemon \
           spiceproxy pve-firewall pve-cluster; do
    systemctl stop "$svc" 2>/dev/null || true
done
rm -f /var/lib/pve-cluster/config.db /var/lib/pve-cluster/config.db-wal \
      /var/lib/pve-cluster/config.db-shm
rm -rf /var/lib/pve-cluster/backup
# /etc/pve is only a mountpoint once pmxcfs is stopped; it must be empty.
if [ -n "$(ls -A /etc/pve 2>/dev/null)" ]; then
    echo "ERROR: /etc/pve not empty after stopping pve-cluster" >&2
    exit 1
fi

# Remove /etc/hostname so MAAS can set it during deployment
# Proxmox installation creates this file, but it must not exist in the image
rm -f /etc/hostname

# Clean up packer-debian hostname from /etc/hosts
# This entry is created during the build process but should not be in the final image
# Remove any line containing "packer-debian"
sed -i '/packer-debian/d' /etc/hosts

# Also remove the build-time IP entry (10.0.2.15 is QEMU NAT default)
sed -i '/^10\.0\.2\.15/d' /etc/hosts

# Clean cloud-init state so it runs fresh on MAAS deployment
# This must run AFTER Proxmox installation since Proxmox packages may trigger cloud-init
echo "Cleaning cloud-init state..."
cloud-init clean --logs --machine-id --seed
