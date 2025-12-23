# MAAS Proxmox Images

Build custom Debian images for MAAS deployment, with the goal of deploying Proxmox VE on bare metal.

## Current Status

This repository contains configurations to build both vanilla Debian 13 (Trixie) and Proxmox VE 9.1 images for MAAS deployment.

## Branches

- **main**: Vanilla Debian 13 (Trixie) - UEFI boot only
- **proxmox**: Debian 13 with Proxmox VE 9.1 pre-installed

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

### 1. Install Dependencies

```bash
# Install Packer
sudo apt update
sudo apt install -y packer qemu-system-x86 qemu-utils ovmf cloud-image-utils

# Add your user to the kvm group
sudo usermod -a -G kvm $USER
newgrp kvm
```

### 2. Build Debian 13 Image

```bash
cd debian
sg kvm -c "make debian SERIES=trixie"
```

This will create `debian-13-cloudimg.tar.gz` (approximately 429MB).

**Build time**: ~10-15 minutes depending on network speed and system performance.

### 3. Upload to MAAS Server

```bash
# Copy tarball to MAAS server
scp debian-13-cloudimg.tar.gz ubuntu@<MAAS_IP>:/home/ubuntu/debian-13-vanilla.tar.gz

# SSH to MAAS server and upload the image
ssh ubuntu@<MAAS_IP>

maas admin boot-resources create \
  name='custom/debian-13-vanilla' \
  title='Debian 13 Vanilla (Trixie)' \
  architecture='amd64/generic' \
  filetype='tgz' \
  content@=/home/ubuntu/debian-13-vanilla.tar.gz
```

**Important**: Replace `admin` with your MAAS profile name and `<MAAS_IP>` with your MAAS server IP address.

### 4. Install Custom Preseed (Required for Debian)

Debian images require a custom preseed file to configure APT sources correctly during deployment:

```bash
# On MAAS server
sudo cp debian/preseed/curtin_userdata_custom_amd64 \
  /var/snap/maas/current/preseeds/curtin_userdata_custom_amd64

# Restart MAAS to load the preseed
sudo systemctl restart snap.maas.supervisor
```

### 5. Deploy via MAAS

1. Go to MAAS web UI
2. Select a machine
3. Click "Deploy"
4. Choose "Debian 13 Vanilla (Trixie)" from the OS dropdown
5. Complete deployment

**Boot Requirements**: UEFI boot must be enabled. Legacy BIOS is not supported for Debian 13 images.

**Default Credentials**: SSH with your MAAS-configured key as user `debian`.

## Building Proxmox VE Images (proxmox branch)

To build a Debian 13 image with Proxmox VE 9.1 pre-installed:

```bash
# Switch to proxmox branch
git checkout proxmox

# Build Proxmox image
cd debian
sg kvm -c "make proxmox SERIES=trixie"
```

This will create `proxmox-ve-13-cloudimg.tar.gz` (approximately 2.5GB).

**Build time**: ~25-35 minutes (longer than vanilla due to Proxmox installation).

### What Gets Installed

The Proxmox build includes:
- Proxmox VE 9.1 (latest packages from pve-no-subscription repository)
- Proxmox kernel (replaces standard Debian kernel)
- Required services: postfix, open-iscsi, chrony
- Web interface accessible at `https://<machine-ip>:8006`

### Upload Proxmox Image to MAAS

```bash
# Copy tarball to MAAS server
scp proxmox-ve-13-cloudimg.tar.gz ubuntu@<MAAS_IP>:/home/ubuntu/proxmox-ve-9.1.tar.gz

# SSH to MAAS server and upload the image
ssh ubuntu@<MAAS_IP>

maas admin boot-resources create \
  name='custom/proxmox-ve-9.1' \
  title='Proxmox VE 9.1 (Debian 13)' \
  architecture='amd64/generic' \
  filetype='tgz' \
  content@=/home/ubuntu/proxmox-ve-9.1.tar.gz
```

### Post-Deployment

After deploying a Proxmox image:

1. Access web interface: `https://<machine-ip>:8006`
2. Login as `root` with the password configured via MAAS
3. Create network bridge `vmbr0` for VM networking
4. Configure storage pools as needed
5. Upload or add a subscription key (or continue with no-subscription repository)

**Note**: The pve-no-subscription repository is used by default. For production use, consider purchasing a Proxmox subscription and updating the repository configuration.

## Build Options

### Default Build (Debian 13 with default kernel)

```bash
sg kvm -c "make debian SERIES=trixie"
```

### Build with Custom Kernel

```bash
sg kvm -c "make debian SERIES=trixie KERNEL=6.17.4-1-pve"
```

### Build for ARM64

```bash
sg kvm -c "make debian SERIES=trixie ARCH=arm64"
```

### BIOS Boot (Separate Build Required)

```bash
sg kvm -c "make debian SERIES=trixie BOOT=bios"
```

Note: UEFI and BIOS images must be built separately for Debian 12+.

## Project Structure

```
MAAS-Proxmox/
├── README.md                           # This file
└── debian/
    ├── Makefile                        # Build automation
    ├── debian-cloudimg.pkr.hcl        # Main Packer configuration
    ├── debian-cloudimg.variables.pkr.hcl
    ├── variables.pkr.hcl
    ├── meta-data                       # Cloud-init metadata
    ├── user-data-cloudimg             # Cloud-init user data
    ├── scripts/
    │   ├── essential-packages.sh      # Install base packages
    │   ├── setup-boot.sh              # Configure bootloader
    │   ├── networking.sh              # Network configuration
    │   ├── install-proxmox.sh         # Install Proxmox VE (proxmox branch)
    │   ├── install-custom-kernel.sh   # Optional kernel install
    │   ├── setup-curtin.sh            # MAAS integration
    │   └── cleanup.sh                 # Image cleanup
    ├── preseed/
    │   └── curtin_userdata_custom_amd64  # MAAS preseed for Debian
    └── ORIGINAL-README.md             # Canonical's packer-maas docs
```

## Troubleshooting

### Image boots to EFI shell

**Cause**: Bootloader not properly installed.

**Fix**: Ensure UEFI boot is enabled in BIOS/IPMI settings, and the custom preseed is installed on the MAAS server.

### Cannot login via SSH

**Default user for Debian images is `debian`, not `ubuntu`:**

```bash
ssh debian@<machine-ip>
```

### Deployment shows wrong Debian version

**Verify the uploaded tarball:**

```bash
# On MAAS server
sudo tar -xzf /var/snap/maas/common/maas/boot-resources/snapshot-*/custom/amd64/generic/debian-13-vanilla/uploaded/root-tgz \
  ./etc/debian_version -O
```

Should output `13.x`. If it shows `12.x`, the wrong file was uploaded.

### Build fails with "permission denied" on /dev/kvm

Ensure your user is in the `kvm` group:

```bash
sudo usermod -a -G kvm $USER
newgrp kvm
```

## Known Issues

- **Debian 13 UEFI boot only**: Separate BIOS builds are required (use `BOOT=bios` make parameter)
- **Legacy boot not working**: Disable legacy boot in BIOS to avoid confusion with multiple boot entries
- **First boot may be slow**: Cloud-init runs package updates and configuration

## References

- [Canonical packer-maas](https://github.com/canonical/packer-maas) - Original upstream repository
- [MAAS Documentation](https://maas.io/docs)
- [Debian Cloud Images](https://cloud.debian.org/images/cloud/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)

## License

This project uses configuration from Canonical's packer-maas repository (AGPL-3.0).

## Contributing

Contributions welcome! Please submit pull requests or open issues for bugs and feature requests.
