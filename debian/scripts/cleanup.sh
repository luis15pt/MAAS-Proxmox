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

export DEBIAN_FRONTEND=noninteractive

# Reset cloud-init so it runs fresh on MAAS deployment
echo "Cleaning cloud-init state..."
cloud-init clean --logs --machine-id --seed

# Everything in /run/packer_backup should be restored.
find /run/packer_backup
cp --preserve -r /run/packer_backup/ /
rm -rf /run/packer_backup

# We had to allow root to ssh for the image setup. Let's try to revert that.
sed -i s/^root:[^:]*/root:*/ /etc/shadow
rm -r /root/.ssh
rm -r /etc/ssh/ssh_host_*

# Clean apt cache and logs
apt-get autoremove --purge -yq || true
apt-get clean -yq

# Remove machine-id so a new one is generated on deployment
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Clean temporary files and logs
rm -rf /tmp/* /var/tmp/*
find /var/log -type f -exec truncate -s 0 {} \;

echo "Cleanup complete."
