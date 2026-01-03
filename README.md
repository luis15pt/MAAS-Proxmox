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
**Build time**: ~35-45 minutes

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
**Build time**: ~35-45 minutes

**What's included**:
- Proxmox VE 9.1 (pve-no-subscription)
- Proxmox kernel 6.17.x
- Cloud-init configured for Proxmox compatibility
- ifupdown2 network management with vmbr0 bridge
- Debug user for console access (debug/proxmox123)
- All Proxmox services start automatically

### 3. Upload to MAAS

```bash
# Copy to MAAS server
scp proxmox-ve-13-cloudimg.tar.gz ubuntu@<MAAS_IP>:/home/ubuntu/

# SSH to MAAS server and register the image
ssh ubuntu@<MAAS_IP>
sudo cp /home/ubuntu/proxmox-ve-13-cloudimg.tar.gz /var/snap/maas/common/
sudo maas admin boot-resources create \
  name='custom/proxmox-ve-9.1' \
  architecture='amd64/generic' \
  filetype='tgz' \
  content@=/var/snap/maas/common/proxmox-ve-13-cloudimg.tar.gz
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

The image automatically configures:
- **ens18** (or detected interface) as manual
- **vmbr0** bridge with MAAS-assigned IP address
- DNS and gateway from MAAS
- systemd-networkd disabled (uses ifupdown2)

This allows VMs to use the vmbr0 bridge for networking.

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

Use debug user for console access:
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

## Advanced Configuration

### Custom Hostname

MAAS automatically sets the hostname based on the machine name in MAAS.

### Custom Network Configuration

The curtin-hooks script automatically converts MAAS netplan configuration to `/etc/network/interfaces` format with vmbr0 bridge.

To customize, edit `debian/scripts/curtin-hooks` before building.

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
