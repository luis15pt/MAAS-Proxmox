#!/bin/bash
set -e

echo "========================================"
echo "Proxmox VE MAAS Image Builder (Docker)"
echo "========================================"
echo ""

# Check if /dev/kvm is accessible
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo "ERROR: Cannot access /dev/kvm"
    echo "Please ensure Docker has access to KVM device"
    exit 1
fi

echo "✓ KVM device accessible"
echo ""

# Navigate to debian directory
cd /build/debian

echo "Cleaning previous builds..."
rm -rf output-* debian-custom-*.gz debian-*-cloudimg.tar.gz proxmox-*.tar.gz seeds-cloudimg.iso OVMF_VARS.fd OVMF_CODE.fd SIZE_CODE.fd SIZE_VARS.fd

echo "Preparing OVMF firmware files..."
# Detect OVMF suffix
if [ -f /usr/share/OVMF/OVMF_CODE.fd ]; then
    OVMF_SFX=""
else
    OVMF_SFX="_4M"
fi
cp -v /usr/share/OVMF/OVMF_CODE${OVMF_SFX}.fd OVMF_CODE.fd
cp -v /usr/share/OVMF/OVMF_VARS${OVMF_SFX}.fd OVMF_VARS.fd
cp -v /usr/share/OVMF/OVMF_CODE${OVMF_SFX}.fd SIZE_CODE.fd
cp -v /usr/share/OVMF/OVMF_VARS${OVMF_SFX}.fd SIZE_VARS.fd

echo ""
echo "Initializing Packer..."
packer init .

echo ""
echo "Installing Packer Ansible plugin..."
packer plugins install github.com/hashicorp/ansible

echo ""
echo "Starting Proxmox VE image build..."
echo "This will take approximately 35-45 minutes..."
echo ""

# Run the build with the same parameters as the Makefile
PACKER_LOG=0 packer build \
    -var debian_series=trixie \
    -var debian_version=13 \
    -var architecture=amd64 \
    -var ovmf_suffix=${OVMF_SFX} \
    -var boot_mode=uefi \
    -var host_is_arm=false \
    -var timeout=1h \
    -var install_proxmox=true \
    -var filename=proxmox-ve-13-cloudimg.tar.gz .

echo ""
echo "========================================"
echo "Build completed successfully!"
echo "========================================"
echo ""
echo "Output: debian/proxmox-ve-13-cloudimg.tar.gz"
ls -lh proxmox-ve-13-cloudimg.tar.gz 2>/dev/null || echo "Warning: Output file not found"
echo ""
