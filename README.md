# MAAS Proxmox VE Image Builder

Build Proxmox VE 9.1 images for automated MAAS deployment on bare metal.

Based on Debian 13 (Trixie) with cloud-init integration for seamless MAAS provisioning. All Proxmox services start automatically after deployment.

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
- Proxmox VE 9.1 (pve-no-subscription)
- Proxmox kernel 6.17.x
- Cloud-init configured for Proxmox compatibility
- ifupdown2 network management with vmbr0 bridge
- Comprehensive network support: bonds, VLANs, static routes, bridges
- All Proxmox services start automatically

### 3. Upload to MAAS

```bash
# Copy to MAAS server
scp proxmox-ve-13-cloudimg.tar.gz ubuntu@<MAAS_IP>:/home/ubuntu/

# SSH to MAAS server and register the image
ssh ubuntu@<MAAS_IP>
sudo maas admin boot-resources create \
  name='custom/proxmox-ve-9.1' \
  architecture='amd64/generic' \
  filetype='tgz' \
  content@=/home/ubuntu/proxmox-ve-13-cloudimg.tar.gz
```

Replace `admin` with your MAAS profile name.

### 4. Deploy

1. MAAS web UI → Select machine → Deploy
2. Choose "Proxmox VE 9.1"
3. After deployment completes, SSH to the machine and set root password:
   ```bash
   ssh debian@<machine-ip>
   sudo passwd root
   # Or use a one-liner:
   echo "root:proxmox" | sudo chpasswd
   ```
4. Access Proxmox web UI at `https://<machine-ip>:8006`
5. Login: root@pam (use the password you just set)

**Note**: The image does not include a default root password for security. You must set it via SSH after deployment to access the web UI.

**Requirements**:
- UEFI boot enabled
- SSH key configured in MAAS
- Secure Boot disabled (or use signed kernels)

## Network Configuration

The curtin-hooks script automatically converts MAAS netplan configuration to Proxmox `/etc/network/interfaces` format during deployment. All network configurations are bridged via **vmbr0** for VM networking.

### Supported Network Topologies

The image supports all MAAS network configurations:

**✅ Simple Ethernet**
- Single interface with static IP
- Automatic vmbr0 bridge creation

**✅ Network Bonds**
- **802.3ad (LACP)**: Requires switch/hypervisor LACP support
- **active-backup**: Automatic failover (no switch config needed)
- **balance-rr, balance-xor, balance-tlb, balance-alb**: All bonding modes supported
- Configurable: miimon, lacp-rate, xmit-hash-policy

**✅ VLANs**
- Tagged VLAN interfaces (e.g., vlan.100, ens18.200)
- VLAN on bonds supported
- Automatic parent interface configuration

**✅ Static Routes**
- Custom routing with metrics
- Multiple routes per interface
- Automatic route configuration on vmbr0

**✅ Bridges**
- MAAS-created bridges automatically detected
- Nested bridge configurations supported

### Network Configuration Examples

**Bond with active-backup** (recommended for virtual environments):
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

**VLAN configuration**:
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

**Priority order**: MAAS bridges → VLANs → Bonds → Ethernet

**Configuration**:
- DNS and gateway from MAAS automatically applied
- systemd-networkd disabled (uses ifupdown2)
- All configurations bridge to vmbr0 for VM networking

## Project Structure

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
    │   └── curtin-hooks                   # MAAS deployment hooks
    └── scripts/
        ├── essential-packages.sh          # Install base packages
        ├── setup-boot.sh                  # Configure UEFI bootloader
        ├── networking.sh                  # Network configuration
        ├── setup-curtin.sh                # Install curtin hooks
        ├── curtin-hooks                   # Network bridge configuration
        └── cleanup.sh                     # Image cleanup
```

## Troubleshooting

### Web UI not accessible after deployment

Check Proxmox services:
```bash
ssh debian@<machine-ip>
sudo systemctl status pve-cluster pveproxy pvedaemon
```

All should show `active (running)`. If not, check:
- `/etc/hosts` contains actual IP (not 127.0.1.1)
- Hostname is set correctly: `hostnamectl`
- Network bridge exists: `ip a show vmbr0`

### Network not working / No vmbr0 bridge

Check network configuration:
```bash
cat /etc/network/interfaces
# Should show vmbr0 bridge with your IP

ip -br a
# Should show vmbr0 with IP address

# Check for conflicting network managers
systemctl status systemd-networkd  # Should be masked
systemctl status networking         # Should be active
```

### Cannot login via console

**Option 1**: SSH in using the default `debian` user and your MAAS SSH key:
```bash
ssh debian@<machine-ip>
sudo -i
```

**Option 2**: Enable debug user (optional)

If you need console access without SSH keys (useful for debugging network issues), you can enable a debug user before building the image:

1. Edit `debian/ansible/proxmox.yml`
2. Uncomment the "Create debug user" and "Enable password authentication" tasks (lines 105-123)
3. Rebuild the image

Default credentials after enabling:
```
Username: debug
Password: proxmox123
```

Then switch to root: `sudo -i`

### Build fails with "permission denied" on /dev/kvm

**For Docker builds:**
```bash
# Ensure KVM_GID is set correctly
export KVM_GID=$(getent group kvm | cut -d: -f3)
sudo -E docker compose up

# Verify KVM device is accessible
ls -l /dev/kvm
```

**For manual builds:**
```bash
sudo usermod -a -G kvm $USER
newgrp kvm
```

### Docker build fails with FUSE errors

Ensure `/dev/fuse` device is available:
```bash
ls -l /dev/fuse
# Should show: crw-rw-rw- 1 root root 10, 229

# If missing, load the fuse module
sudo modprobe fuse
```

### Image boots to EFI shell

- Enable UEFI boot in BIOS/IPMI settings
- Disable Secure Boot (Proxmox kernel is not signed)
- Ensure MAAS deployed the image correctly

### Bond shows NO-CARRIER or not working

**For 802.3ad (LACP) bonds:**
- LACP requires **both sides** to be configured (machine + switch/hypervisor)
- If deploying VMs in Proxmox/VMware, the hypervisor must also have LACP configured
- **Solution**: Use **active-backup** mode instead (works without switch configuration)

**For active-backup bonds:**
- Check `ip a` - bond0 should show one interface as ACTIVE
- Check `cat /proc/net/bonding/bond0` for bond status
- Verify both slave interfaces are UP: `ip link show ens18 ens19`

**To change bond mode in MAAS:**
1. MAAS web UI → Machine → Network → Edit bond
2. Change mode from "802.3ad" to "active-backup"
3. Redeploy machine

## Advanced Configuration

### Custom Hostname

MAAS automatically sets the hostname based on the machine name in MAAS.

### Custom Network Configuration

The curtin-hooks script automatically converts MAAS netplan configuration to `/etc/network/interfaces` format with vmbr0 bridge. Supports bonds, VLANs, static routes, and all MAAS network topologies (see **Network Configuration** section above).

To customize network conversion logic, edit `debian/scripts/curtin-hooks` before building. Remember to sync changes to `debian/curtin/curtin-hooks` as well.

### Cloud-init Configuration

Proxmox-specific cloud-init configs are in `debian/ansible/proxmox.yml`:
- Disables cloud-init network management
- Configures /etc/hosts for Proxmox requirements
- Sets up bootcmd to ensure correct hostname resolution

## References

- [Canonical packer-maas](https://github.com/canonical/packer-maas) - Original upstream repository
- [MAAS Documentation](https://maas.io/docs)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Debian 13 Trixie](https://www.debian.org/releases/trixie/)

## License

This project uses configuration from Canonical's packer-maas repository (AGPL-3.0).

## Contributing

Contributions welcome! Please submit pull requests or open issues for bugs and feature requests.
