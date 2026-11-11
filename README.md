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
- Sufficient disk space (~5GB for build artifacts)
- User must be member of the `kvm` group

### MAAS Server

- MAAS 3.x or later
- Network connectivity to build machine
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

**Output**: `debian/proxmox-ve-13-cloudimg.tar.gz` (~2.4GB)
**Build time**: ~45-55 minutes

The container will automatically clean up after the build completes. The output file will be in the `debian/` directory.

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

**Output**: `proxmox-ve-13-cloudimg.tar.gz` (~2.4GB)
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
- ✅ **MAAS Settings**: SSH key configured in MAAS

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

The curtin-hooks script automatically converts MAAS netplan to Proxmox `/etc/network/interfaces` format. All configurations are bridged via **vmbr0** for VM networking.

**Supported:**
- ✅ Simple Ethernet, Bonds (802.3ad LACP, active-backup, etc.)
- ✅ VLANs, Static Routes, Nested Bridges

**Bond with active-backup example** (recommended for virtual environments):
```
auto ens18
iface ens18 inet manual
    bond-master bond0

auto ens19
iface ens19 inet manual
    bond-master bond0

auto bond0
iface bond0 inet manual
    bond-slaves ens18 ens19
    bond-mode active-backup
    bond-miimon 100

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.10/24
    gateway 192.168.1.1
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
```

**VLAN example**:
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
    bridge-ports vlan100
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
3. ✅ **Enable "Sync hardware"** checkbox (syncs vmbr0 bridge back to MAAS for visibility)
4. Click **Deploy** (~10-15 minutes)

### Post-Deployment

```bash
# SSH to deployed machine
ssh debian@<machine-ip>

# Set root password for Proxmox UI access
echo "root:your-password" | sudo chpasswd

# Access Proxmox web UI
# https://<machine-ip>:8006
# Login: root@pam
```

**Optional post-deployment tasks:**
- Disable subscription nag: Edit `/etc/apt/sources.list.d/pve-enterprise.list`
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

To enable debug console user, edit `debian/ansible/proxmox.yml` before building and uncomment debug user tasks (lines 105-123).

**Build failures**

KVM permission denied:
```bash
export KVM_GID=$(getent group kvm | cut -d: -f3)
sudo -E docker compose up
```

FUSE errors: `sudo modprobe fuse`

**Boots to EFI shell**

Ensure UEFI boot is enabled in BIOS/IPMI. Secure Boot is supported but may need to be disabled on some firmware that doesn't trust the Debian shim.

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

## References

- [Canonical packer-maas](https://github.com/canonical/packer-maas) - Original upstream (AGPL-3.0)
- [MAAS Documentation](https://maas.io/docs)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)

Contributions welcome! Submit PRs or open issues at [github.com/luis15pt/MAAS-Proxmox](https://github.com/luis15pt/MAAS-Proxmox)
