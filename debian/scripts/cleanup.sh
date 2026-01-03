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
