# MAAS Proxmox VE Image Builder

Build Proxmox VE 9 images (Debian 13 "Trixie" + cloud-init) for automated MAAS deployment on bare metal. All Proxmox services start automatically after deployment.

- [Prerequisites](#prerequisites)
- [Build](#build)
- [Upload to MAAS](#upload-to-maas)
- [Deploy](#deploy)
- [After deployment: access (required)](#after-deployment-access-required)
- [Troubleshooting](#troubleshooting)
- [Tested with](#tested-with)

## Prerequisites

**Build machine:** Ubuntu 22.04+, KVM/QEMU, ~15 GB free disk, user in the `kvm` group. Docker + Compose for the recommended build.

**MAAS:** 3.x or later (tested 3.8.0 snap); PXE/DHCP on the deployment VLAN (MAAS-managed DHCP, or an external DHCP server pointing at MAAS with next-server + `bootx64.efi`); enough RAM to accept a ~3 GB upload.

## Build

**Docker (recommended):**

```bash
git clone https://github.com/luis15pt/MAAS-Proxmox.git && cd MAAS-Proxmox
export KVM_GID=$(getent group kvm | cut -d: -f3)
sudo -E docker compose up          # or: up -d, then: sudo docker compose logs -f
```

**Native:**

```bash
sudo apt install -y packer qemu-system-x86 qemu-utils ovmf cloud-image-utils
sudo usermod -a -G kvm $USER && newgrp kvm
cd debian && packer plugins install github.com/hashicorp/ansible
sg kvm -c "make proxmox"
```

Output: `debian/proxmox-ve-13-cloudimg.tar.gz` (~2.9 GB) after ~45-55 minutes.

> ⚠️ Each build deletes the previous output first (`debian/*.tar.gz`, `output-*`, OVMF files). Move an image you want to keep out of `debian/` before rebuilding.

**What the image contains:**
- Proxmox VE 9.x from pve-no-subscription at build time (9.2 / kernel 7.0 as of Nov 2026); the enterprise repo ships disabled (`Enabled: no`), so `apt-get update` works without a subscription
- Secure Boot support (shim + proxmox-secure-boot-support) and an EFI fallback boot path
- ifupdown2 with `vmbr0`; bonds, VLANs, static routes and MTU from MAAS are converted by `curtin-hooks`
- Key-only SSH and locked passwords (see [access](#after-deployment-access-required))
- No build-time secrets: the build VM's Proxmox cluster database is removed, so every host generates its own CA, API ticket key, node certificate and root SSH key on first boot

## Upload to MAAS

```bash
scp debian/proxmox-ve-13-cloudimg.tar.gz ubuntu@<MAAS_IP>:/home/ubuntu/
ssh ubuntu@<MAAS_IP>
sudo maas admin boot-resources create name='proxmox-ve-9.1' title='Proxmox VE 9.1' \
  architecture='amd64/generic' filetype='tgz' base_image='ubuntu/noble' \
  content@=/home/ubuntu/proxmox-ve-13-cloudimg.tar.gz
# wait for "complete": true before deploying
sudo maas admin boot-resource read <ID> | jq '[.sets[] | {version, complete}]'
```

Replace `admin` with your MAAS profile. Use the **bare name** `proxmox-ve-9.1` (MAAS 3.8 stores a `custom/` prefix literally, then can't find the image at deploy time). With the MAAS snap, if `content@=` gives `Permission denied`, copy the file to `/var/snap/maas/common/` first.

## Deploy

**Before deploying, in MAAS:**

- ✅ **Your SSH public key is in your MAAS user. Required:** it is the *only* way into a fresh host (no passwords exist, see below). The login user is `debian` with passwordless `sudo`.
- ✅ **Interfaces set to Auto assign or Static assign, never DHCP**: `curtin-hooks` needs a static address to write `/etc/network/interfaces`.
- ✅ **Bonds with `mii-monitor-interval` 100** (0 disables link detection and failover).
- ✅ **No bridges in MAAS**: `vmbr0` is created automatically (a MAAS bridge is replaced by `vmbr0` with the same ports).
- ✅ **UEFI boot** enabled on the machine.

> ⚠️ **Keeping data disks (e.g. reinstalling a Ceph node):** MAAS puts **every disk it knows about** into the curtin storage config with `wipe: superblock`, even disks shown as "Unused". Delete those disks from the machine's Storage tab first (this only removes MAAS's record), then, right after starting the deploy, check that only the OS disk is listed: `maas <profile> machine get-curtin-config <system_id>` (works only while Deploying). Re-commissioning adds the disks back.

**Deploy:** MAAS UI → machine → **Deploy** → OS **"Proxmox VE 9.1"** → Deploy (~10-15 min bare metal). CLI: `osystem=custom distro_series=proxmox-ve-9.1`.

> **"Sync hardware" (optional):** installs `maas_hardware_sync.timer`, which keeps a MAAS API token on the host and runs a MAAS-provided script as root every 15 minutes, so whoever controls MAAS controls the host. Leave it off unless you need it.

**Network conversion:** every interface MAAS defines is written (NICs, bonds with mode/miimon/LACP rate/hash policy, VLANs, MTU). `vmbr0` goes on the interface with the default gateway; other IPs stay on their own interface with their routes. Example, management IP on a bond plus a tagged VLAN:

```
auto bond0
iface bond0 inet manual
    bond-slaves enp6s18 enp6s19
    bond-mode active-backup
    bond-miimon 100

auto bond0.3999
iface bond0.3999 inet static
    address 192.0.2.10/24
    vlan-raw-device bond0
    vlan-id 3999

auto vmbr0
iface vmbr0 inet static
    address 192.168.8.229/24
    gateway 192.168.8.254
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
```

**Storage:** the default flat layout (EFI + ext4 root on one disk) is tested. Other MAAS layouts (e.g. `storage_layout=lvm`) may work but are untested. VM storage after deployment is the directory `/var/lib/vz`. Don't use MAAS software RAID for the boot disk: MAAS puts the EFI partition on the md array, which UEFI can't read.

## After deployment: access (required)

For security, a deployed host has **no usable password**: `root` (`*`) and `debian` (`!`) are locked, and SSH is key-only (`/etc/ssh/sshd_config.d/00-maas-proxmox.conf`: `PasswordAuthentication no`, `PermitRootLogin prohibit-password`). You get in with `ssh debian@<host>` and the key from MAAS, then `sudo -i`.

So the **Proxmox web UI (port 8006) can't be used until you create a login.** What a Proxmox cluster shares: users, groups, permissions, realms and TOTP (they live in `/etc/pve`). What it doesn't share: `@pam` passwords, which are each node's own Linux password.

**Recommended: one admin in the Proxmox VE realm.** It works on every node of a cluster, and you only set it once:

```bash
sudo pveum user add <name>@pve
sudo pveum acl modify / --users <name>@pve --roles Administrator
sudo pveum passwd <name>@pve        # type it yourself; stored cluster-wide in /etc/pve/priv/shadow.cfg
```

Log in at `https://<host>:8006` with:
- **User name: `<name>` only, without `@pve`.** The realm dropdown adds `@pve`; typing it yourself gives `<name>@pve@pve` and "no such user".
- **Realm: "Proxmox VE authentication server".**

Then add TOTP under Datacenter → Permissions → Two Factor (shared cluster-wide).

**Break-glass: a root password on each node.** Some actions are `root@pam`-only (for example some hardware/passthrough settings without a resource mapping), and you need it at the console if the cluster filesystem is broken. Set it per node with `sudo passwd root` and keep it in a password manager. It does **not** enable password SSH.

Also note: once a host joins a cluster, root's `authorized_keys` becomes the cluster-wide `/etc/pve/priv/authorized_keys`.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| No `vmbr0` / no network | Interface was set to DHCP in MAAS. Release, set Auto assign, redeploy. Check `cat /etc/network/interfaces`, `ip -br a`; for bonds `bond-miimon 100` and `/proc/net/bonding/bond0`. |
| Web UI login fails | No login created yet (see [access](#after-deployment-access-required)), or `@pve` typed in the user name. |
| Web UI not reachable | `systemctl status pve-cluster pveproxy pvedaemon`; `/etc/hosts` must map the host name to its real IP (not 127.0.1.1). |
| `cannot identify base image compatible with amd64/generic` | Uploaded as `custom/<name>`; re-upload with the bare name. |
| `Missing boot image` right after upload | Upload not processed yet; wait for `"complete": true`. |
| Upload HTTP 500 / timed out | MAAS region workers out of memory after several ~3 GB uploads: `sudo snap restart maas`, retry; add swap/RAM. |
| Curtin `apt-get update` 401 from enterprise.proxmox.com | Image built before the enterprise-repo fix; rebuild from `main`. |
| Host waits minutes at boot | UEFI BootOrder keeps PXE first (normal for MAAS). If MAAS/DHCP is unreachable the firmware waits for the PXE timeout. Keep MAAS reachable, or move `debian` first with `efibootmgr -o`. |
| Boots to the EFI shell | UEFI not enabled, or the built-in EFI Shell sits ahead of `debian` in BootOrder (seen on Cisco UCS): `efibootmgr -o <PXE>,<debian>,…`. Secure Boot works when the firmware trusts the Microsoft UEFI CA. |
| Cisco UCS (CIMC): MAAS power state "error" after enlistment | The `maas` IPMI user MAAS created is disabled; enable it in CIMC → User Management. `ipmitool chassis bootdev pxe` may be ignored; force network boot from the BIOS boot menu for enlistment. |
| SSH host key fingerprint in MAAS logs doesn't match | MAAS's rsyslog shows keys from the temporary Ubuntu install environment, not the installed host. Verify on the host's console instead. |
| Build: KVM permission denied / FUSE errors | `export KVM_GID=…` and `sudo -E`; `sudo modprobe fuse`. |

A console debug user (debug only, public password) can be enabled before building in `debian/ansible/proxmox.yml` ("Optional: Create debug user"); never ship that image.

**Project layout:** `Dockerfile`, `docker-compose.yml`, `docker-entrypoint.sh` (Docker build); `debian/debian-cloudimg.pkr.hcl` + variables (Packer); `debian/ansible/proxmox.yml` (installs/configures Proxmox, cloud-init settings); `debian/curtin/curtin-hooks` (network → `vmbr0`, apt, kernel; the only copy, installed as `/curtin/curtin-hooks`); `debian/scripts/` (packages, boot, networking, cleanup).

## Tested with

- MAAS 3.8.0 (snap), MAAS-managed DHCP.
- Proxmox VE VM target (q35, OVMF with Secure Boot keys, virtio): commission → deploy OK; PVE 9.2.26, kernel 7.0.14; single NIC; active-backup bond + tagged VLAN with its own IP (0% loss on NIC failover). LACP, VLAN-on-NIC and multi-IP layouts were checked by rendering MAAS configs through the hook.
- Bare metal, 802.3ad LACP bond of two 10G NICs to a Cisco Nexus port-channel, MTU 9000, static IP, OS on one SSD with existing Ceph OSD disks kept; nodes rejoined an existing Proxmox/Ceph cluster and the OSDs came back with their data:
  - Supermicro X10SDV-8C-TLN4F+ (IPMI), 2 nodes.
  - Cisco UCS C240 M4 (CIMC, UEFI), 2 nodes (9 OSDs each).

## References

- [Canonical packer-maas](https://github.com/canonical/packer-maas): original upstream (AGPL-3.0)
- [MAAS documentation](https://maas.io/docs) · [Proxmox VE documentation](https://pve.proxmox.com/pve-docs/)

Contributions welcome: open issues or PRs at [github.com/luis15pt/MAAS-Proxmox](https://github.com/luis15pt/MAAS-Proxmox).
