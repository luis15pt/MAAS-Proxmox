# MAAS Proxmox VE Image Builder

Build Proxmox VE 9 images for automated MAAS deployment on bare metal.

Based on Debian 13 (Trixie) with cloud-init integration for seamless MAAS provisioning. All Proxmox services start automatically after deployment.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Deployment Guide](#deployment-guide)
- [Advanced Topics](#advanced-topics)
- [References](#references)

## Prerequisites

### Build Machine

- Ubuntu 22.04 or later
- Packer installed
- KVM/QEMU support
- Sufficient disk space (~15GB free: the build VM disk plus the ~2.9GB tarball)
- User must be member of the `kvm` group

### MAAS Server

- MAAS 3.x or later (tested with MAAS 3.8.0, snap)
- PXE/DHCP on the deployment VLAN: either MAAS-managed DHCP or an external DHCP server pointing at MAAS (next-server + `bootx64.efi`)
- Enough RAM on the MAAS server to accept ~3GB uploads (see "MAAS upload / deploy errors" under Troubleshooting)
- SSH access for file transfers

## Quick Start

### Option A: Build with Docker (Recommended)

The easiest way to build the image is using Docker, which handles all dependencies automatically.

**Prerequisites:**
- Docker and Docker Compose installed
- KVM support on the host machine

```bash
# Clone the repository
git clone https://github.com/luis15pt/MAAS-Proxmox.git
cd MAAS-Proxmox

# Set KVM group ID for your system
export KVM_GID=$(getent group kvm | cut -d: -f3)

# Build the image using Docker
sudo -E docker compose up

# Or run in background and monitor logs
sudo -E docker compose up -d
sudo docker compose logs -f
```

**Note:** The `-E` flag preserves the `KVM_GID` environment variable when using sudo.

**Output**: `debian/proxmox-ve-13-cloudimg.tar.gz` (~2.9GB)
**Build time**: ~45-55 minutes

The output file will be in the `debian/` directory.

> **⚠️ Each build deletes the previous output first** (`debian/*.tar.gz`, `output-*`, OVMF files). Move an image you want to keep out of `debian/` before rebuilding.

### Option B: Manual Build (Native)

### 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y packer qemu-system-x86 qemu-utils ovmf cloud-image-utils

# Add user to kvm group
sudo usermod -a -G kvm $USER
newgrp kvm
```

### 2. Build Proxmox VE Image

```bash
cd debian

# Install packer ansible plugin
packer plugins install github.com/hashicorp/ansible

# Build Proxmox VE image
sg kvm -c "make proxmox"
```

**Output**: `proxmox-ve-13-cloudimg.tar.gz` (~2.9GB)
**Build time**: ~45-55 minutes

**What's included**:
- Proxmox VE 9.x, latest from pve-no-subscription at build time (9.2 as of Nov 2026)
- Proxmox default kernel (7.0.x as of Nov 2026)
- Secure Boot support (proxmox-secure-boot-support + shim)
- Cloud-init configured for Proxmox compatibility
- ifupdown2 network management with vmbr0 bridge
- Comprehensive network support: bonds, VLANs, static routes, bridges
- EFI fallback boot path for broad firmware compatibility
- Proxmox no-subscription apt repositories preserved during deployment; the enterprise repo ships disabled (`Enabled: no`) so `apt-get update` works without a subscription
- Key-only SSH (`PasswordAuthentication no`, root key login only); root and `debian` passwords locked, so the web UI needs a post-install step (see [Required: enable web UI access](#required-enable-web-ui-access))
- No build-time secrets: the Proxmox cluster database from the build VM is removed, so each host generates its own CA, API ticket key, node certificate and root SSH key on first boot; root's `authorized_keys` holds only the MAAS-supplied key and the host's own root key
- All Proxmox services start automatically

### 3. Upload to MAAS

```bash
# Copy to MAAS server
scp proxmox-ve-13-cloudimg.tar.gz ubuntu@<MAAS_IP>:/home/ubuntu/

# SSH to MAAS server and register the image
ssh ubuntu@<MAAS_IP>
sudo maas admin boot-resources create \
  name='proxmox-ve-9.1' \
  title='Proxmox VE 9.1' \
  architecture='amd64/generic' \
  filetype='tgz' \
  base_image='ubuntu/noble' \
  content@=/home/ubuntu/proxmox-ve-13-cloudimg.tar.gz

# Wait until the upload is processed ("complete": true) before deploying
sudo maas admin boot-resources read | jq '.[] | select(.name|test("proxmox")) | {id, name}'
sudo maas admin boot-resource read <ID> | jq '[.sets[] | {version, complete}]'
```

Replace `admin` with your MAAS profile name.

**Notes:**
- Use the bare name (`proxmox-ve-9.1`), not `custom/proxmox-ve-9.1`. MAAS 3.8 stores the
  `custom/` prefix literally but looks the image up by its bare name at deploy time, so a
  prefixed upload fails with "cannot identify base image compatible with amd64/generic".
- Deploying before the set is `complete` fails with "Missing boot image".
- With the MAAS snap, `content@=` must be readable by root inside the snap. If you get
  `Permission denied`, copy the file to `/var/snap/maas/common/` first.
- From the CLI, deploy with `osystem=custom distro_series=proxmox-ve-9.1`.

**Next**: See [Deployment Guide](#deployment-guide) for network configuration and deployment steps.

## Deployment Guide

### Pre-Deployment Checklist

**⚠️ CRITICAL: Configure these in MAAS BEFORE deploying:**

- ✅ **Network IP Mode**: Use "Auto assign" or "Static assign" - **NEVER "DHCP"** (curtin-hooks requires static IPs)
- ✅ **Bond Link Monitoring**: If using bonds, set `mii-monitor-interval` to `100` (not `0`)
- ✅ **No Bridges**: Do NOT create bridges in MAAS (vmbr0 is created automatically)
- ✅ **BIOS Settings**: UEFI enabled, Secure Boot supported
- ✅ **MAAS Settings (REQUIRED)**: your SSH public key added to your MAAS user (the deployed login user is `debian`, with passwordless sudo). **This is the only way into a freshly deployed host**: the image has no password logins at all (see [Access model](#access-model-no-passwords-by-design)). Deploy without a key and you will have to redeploy.

> **⚠️ Keeping data disks (e.g. reinstalling a Ceph node):** MAAS puts **every disk it knows about** into the curtin storage config with `wipe: superblock`, even disks the UI shows as "Unused". Deploying would wipe them (Ceph OSDs included). Before deploying, delete those disks from the machine's Storage tab in MAAS (this only removes MAAS's record, not the data), then check right after starting the deploy that only the OS disk is listed: `maas <profile> machine get-curtin-config <system_id>` (it only works while the machine is Deploying). Re-commissioning adds the disks back.

<details>
<summary><h3>Why These Settings Matter</h3></summary>

**Auto-assign vs DHCP:**
- **Auto-assign**: MAAS writes a permanent static IP to `/etc/network/interfaces` during deployment
- **DHCP**: Machine requests IP at runtime - curtin-hooks can't detect this (no `addresses` field in config) and leaves network unconfigured

**Bond link monitoring:**
- `mii-monitor-interval: 0` disables link state detection
- Bond can't detect which interface is connected, may use disconnected cable
- Set to `100` (checks every 100ms) for reliable failover

**Bridges:**
- Curtin-hooks automatically creates vmbr0 bridge during deployment
- Pre-existing MAAS bridges cause conflicts with Proxmox network configuration

</details>

### Network Configuration

<details>
<summary><h4>Supported Network Topologies</h4></summary>

The curtin-hooks script converts the MAAS netplan config to Proxmox `/etc/network/interfaces`:

- **Every interface MAAS defines is written**: physical NICs, bonds (mode, miimon, LACP rate, hash policy, up/down delay) and VLANs, with their MTU.
- **vmbr0 goes on the interface that has the default gateway** (falls back to the first interface with an IP, in bridge > VLAN > bond > NIC order). VMs use vmbr0.
- **Other IPs stay on their own interface** as static addresses (for example a storage VLAN), with their static routes. Only one default gateway is used.
- A bridge created in MAAS is replaced by vmbr0 with the same ports.

**Supported:**
- ✅ Simple Ethernet, Bonds (802.3ad LACP, active-backup, etc.)
- ✅ VLANs on NICs or bonds, multiple IP interfaces, static routes, MTU (jumbo frames)

**Example: management IP on a bond plus a VLAN with its own IP** (tested: deploy, failover, tagged traffic):
```
auto enp6s18
iface enp6s18 inet manual

auto enp6s19
iface enp6s19 inet manual

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

**VLAN on a single NIC** (VMs on vmbr0 land in VLAN 100):
```
auto ens18
iface ens18 inet manual

auto vlan100
iface vlan100 inet manual
    vlan-raw-device ens18
    vlan-id 100

auto vmbr0
iface vmbr0 inet static
    address 192.168.100.10/24
    gateway 192.168.100.1
    bridge-ports vlan100
    bridge-stp off
    bridge-fd 0
```

</details>

### Storage Configuration

<details>
<summary><h4>Tested Storage Layouts</h4></summary>

| Layout | Best For | How to Configure |
|--------|----------|------------------|
| **Flat** (Default) | Most deployments | No configuration needed |
| **LVM** | Flexibility, snapshots | `maas $PROFILE machine set-storage-layout $SYSTEM_ID storage_layout=lvm` |
| **ZFS** | Production, data integrity, 16GB+ RAM | MAAS UI → Storage → Delete partitions → Add ZFS partition + EFI |

All layouts use directory storage at `/var/lib/vz` for VMs/containers after deployment.

</details>

### Deploy

1. **MAAS UI** → Select machine → **Deploy**
2. Choose **"Proxmox VE 9.1"** OS
3. Optional: **"Sync hardware"** (syncs the vmbr0 bridge back to MAAS for visibility). See the security note below before enabling it.
4. Click **Deploy** (~10-15 minutes on bare metal, ~5 minutes on a VM)

> **Security note on "Sync hardware":** it installs `maas_hardware_sync.timer`, which keeps a MAAS API token on the host and runs a MAAS-provided script as root every 15 minutes. Anyone who controls your MAAS server then controls every synced hypervisor. Leave it off unless you need the inventory sync, and keep MAAS on a management network.

### Post-Deployment

#### Access model: no passwords by design

For security, a deployed host has **no usable password anywhere**:

| Account | Password | How you get in |
|---------|----------|----------------|
| `debian` (cloud-init default user) | locked | SSH with the key(s) from your MAAS user; passwordless `sudo` |
| `root` | locked (`*`) | not via SSH at first (cloud-init `disable_root`); use `sudo -i` from `debian` |
| SSH | `PasswordAuthentication no`, `PermitRootLogin prohibit-password` | keys only (`/etc/ssh/sshd_config.d/00-maas-proxmox.conf`) |

Consequences:
- **No SSH key in MAAS = no access.** There is no console or SSH password to fall back on; redeploy with a key (or boot a rescue shell from the BMC console).
- **The Proxmox web UI (port 8006) cannot be used until you complete the step below**, because `root@pam` authenticates against the locked root password.
- After the host joins a Proxmox cluster, root's `authorized_keys` becomes the cluster-wide `/etc/pve/priv/authorized_keys`, so root SSH works with whatever keys that file holds.

#### Required: enable web UI access

Do **one** of these after every deployment:

```bash
ssh debian@<machine-ip>

# Option 1: give root a password (web UI only; SSH stays key-only)
sudo passwd root        # prompts; keeps it out of shell history
# then log in at https://<machine-ip>:8006 as root, realm "Linux PAM"

# Option 2 (recommended): keep root locked, create a dedicated admin in the Proxmox realm
sudo pveum user add admin@pve
sudo pveum passwd admin@pve
sudo pveum acl modify / --users admin@pve --roles Administrator
# then log in at https://<machine-ip>:8006 as admin, realm "Proxmox VE authentication server"
```

Setting a root password does **not** enable password SSH. Remove
`/etc/ssh/sshd_config.d/00-maas-proxmox.conf` only if you really want password SSH (not recommended).
In a cluster, `pve`-realm users exist cluster-wide, so Option 2 is done once; a root password must be set on each node.

**Optional post-deployment tasks:**
- Enterprise repo: ships disabled in `/etc/apt/sources.list.d/pve-enterprise.sources` (`Enabled: no`); set it to `yes` if you add a subscription. (The "No valid subscription" login popup is a separate UI notice.)
- Update packages: `apt update && apt upgrade`
- Configure additional storage or join Proxmox cluster

<details>
<summary><h2>Advanced Topics</h2></summary>

<details>
<summary><h3>Project Structure</h3></summary>

```
MAAS-Proxmox/
├── README.md
├── Dockerfile                             # Docker build environment
├── docker-compose.yml                     # Docker orchestration
├── docker-entrypoint.sh                   # Docker build script
├── .dockerignore                          # Docker build exclusions
└── debian/
    ├── Makefile                            # Build automation (manual builds)
    ├── debian-cloudimg.pkr.hcl            # Main Packer configuration
    ├── debian-cloudimg.variables.pkr.hcl  # Packer variables
    ├── variables.pkr.hcl                  # Additional variables
    ├── meta-data                          # Cloud-init metadata
    ├── user-data-cloudimg                 # Cloud-init user data
    ├── ansible/
    │   └── proxmox.yml                    # Install & configure Proxmox VE
    ├── curtin/
    │   └── curtin-hooks                   # MAAS deployment hooks (network → vmbr0, apt, kernel)
    └── scripts/
        ├── essential-packages.sh          # Install base packages
        ├── setup-boot.sh                  # Configure UEFI bootloader
        ├── networking.sh                  # Network configuration
        ├── setup-curtin.sh                # Install curtin hooks
        └── cleanup.sh                     # Image cleanup
```

</details>

<details>
<summary><h3>Troubleshooting</h3></summary>

**Network not working / No vmbr0 bridge**

Check if you used DHCP mode (most common cause):
```bash
# In MAAS, verify interface shows Auto-assign or Static, NOT DHCP
# If DHCP: Release machine, change to Auto-assign, redeploy

# On deployed machine, check configuration:
cat /etc/network/interfaces  # Should show vmbr0 with IP
ip -br a                     # Should show vmbr0 with IP
```

If using bonds, verify `bond-miimon` is not 0:
```bash
cat /etc/network/interfaces  # Look for "bond-miimon 100" (not 0)
cat /proc/net/bonding/bond0  # Check bond status and active slave
```

**Web UI not accessible**

```bash
ssh debian@<machine-ip>
sudo systemctl status pve-cluster pveproxy pvedaemon  # Should be active

# Check hostname resolution
cat /etc/hosts        # Should contain actual IP, not 127.0.1.1
hostnamectl           # Verify hostname is set
```

**Cannot login via console**

SSH using MAAS key: `ssh debian@<machine-ip>` then `sudo -i`

To enable a debug console user, edit `debian/ansible/proxmox.yml` before building and uncomment the "Optional: Create debug user" tasks. **Debug only:** the commented hash is the public password `proxmox123`; change it, and never ship that image to production. SSH password login stays off either way (see `00-maas-proxmox.conf`), so the user is for the console.

**Verifying the SSH host key**

MAAS's rsyslog shows host key fingerprints printed during deployment, but those come from the temporary Ubuntu install environment, not the installed Proxmox. Compare against the installed system instead (for example the console after first boot, or the disk).

**Build failures**

KVM permission denied:
```bash
export KVM_GID=$(getent group kvm | cut -d: -f3)
sudo -E docker compose up
```

FUSE errors: `sudo modprobe fuse`

**Boots to EFI shell**

Ensure UEFI boot is enabled in BIOS/IPMI. Secure Boot works with firmware that has the Microsoft UEFI CA (tested: OVMF with pre-enrolled keys); disable it only on firmware that doesn't trust the shim.

**MAAS upload / deploy errors**

| Symptom | Cause / fix |
|---------|-------------|
| `cannot identify base image compatible with amd64/generic` | Image uploaded as `custom/<name>`. Re-upload with the bare name (see [Upload to MAAS](#3-upload-to-maas)). |
| `Missing boot image custom/amd64/...` right after upload | Upload not processed yet. Wait for `"complete": true`. |
| `[Errno 13] Permission denied` on `content@=` | MAAS snap can't read the file. Copy it to `/var/snap/maas/common/`. |
| Upload returns HTTP 500 / `timed out` | MAAS region workers ran out of memory (several ~3GB uploads, no swap). `sudo snap restart maas`, then retry; give the MAAS server swap or more RAM. |
| Deploy fails in curtin with `apt-get update` 401 from `enterprise.proxmox.com` | Image built before the enterprise-repo fix. Rebuild from current `main`. |
| Deployed host waits minutes at boot before starting Proxmox | UEFI BootOrder keeps PXE first (normal for MAAS: it answers each PXE boot with "boot local disk"). If MAAS/DHCP isn't reachable, the firmware waits for the PXE timeout and then boots from disk. Keep MAAS reachable, or move the `debian` entry first with `efibootmgr -o` if the host leaves MAAS. |

**RAID boot not working**

MAAS places the EFI System Partition on the md array (e.g., `md0p1`). UEFI firmware cannot read md devices, so the bootloader is never found. This is a MAAS storage layout limitation. Workaround: use a single-disk layout for the boot disk, or use a separate physical disk for the EFI partition.

</details>

<details>
<summary><h3>Custom Configuration</h3></summary>

**Hostname:** Set by MAAS machine name automatically

**Network conversion logic:** Edit `debian/curtin/curtin-hooks` before building (the only copy; it is installed into the image at `/curtin/curtin-hooks`)

**Cloud-init config:** See `debian/ansible/proxmox.yml` for Proxmox-specific settings

</details>

</details>

## Tested With

- MAAS 3.8.0 (snap), MAAS-managed DHCP, manual power
- Proxmox VE VM as the target: q35, OVMF with Secure Boot keys enrolled, virtio NIC, 32GB virtio-scsi disk
- Result: commission → deploy OK; PVE 9.2.26 on kernel 7.0.14-pve; vmbr0 static IP; all PVE services active; web UI on :8006; `apt-get update` clean; SSH key-only
- Network layouts: single NIC; active-backup bond (2 NICs) with the management IP + a tagged VLAN with its own IP: deploy OK, 0% ping loss when the active NIC went down, VLAN frames leave tagged. LACP, VLAN-on-NIC, VLAN-only-IP-on-bond, two NICs with separate IPs and MAAS-bridge layouts were checked by rendering MAAS-style configs through the hook.
- Bare metal: Supermicro X10SDV-8C-TLN4F+ (UEFI, IPMI power), 802.3ad LACP bond of two 10G NICs to a Cisco Nexus port-channel, MTU 9000, static IP: deploy OK; OS on the boot SSD only, the two Ceph OSD disks kept (after removing them from MAAS, see the Pre-Deployment Checklist), node rejoined an existing Proxmox/Ceph cluster and the OSDs were reactivated with their data.

## References

- [Canonical packer-maas](https://github.com/canonical/packer-maas) - Original upstream (AGPL-3.0)
- [MAAS Documentation](https://maas.io/docs)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)

Contributions welcome! Submit PRs or open issues at [github.com/luis15pt/MAAS-Proxmox](https://github.com/luis15pt/MAAS-Proxmox)
