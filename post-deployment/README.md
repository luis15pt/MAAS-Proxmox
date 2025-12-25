# Post-Deployment Proxmox Installation

After deploying a machine via MAAS with the Proxmox-ready Debian 13 image, follow these steps to install Proxmox VE.

## Prerequisites

- Machine successfully deployed via MAAS
- Hostname properly configured by MAAS (not "localhost")
- Network connectivity established
- SSH access as user `debian`

## Installation Steps

### Option A: Two-Step Manual Installation

**Step 1: Install Proxmox kernel and reboot**

```bash
ssh debian@<deployed-ip> 'sudo bash -s' < install-proxmox-post-deploy.sh
```

Wait for the machine to reboot (~1 minute).

**Step 2: Complete Proxmox installation**

```bash
ssh debian@<deployed-ip> 'sudo bash -s' < install-proxmox-step2.sh
```

### Option B: Single Script (handles reboot automatically)

```bash
# Copy scripts to deployed host
scp install-proxmox-*.sh debian@<deployed-ip>:~

# SSH to host and run
ssh debian@<deployed-ip>
sudo bash install-proxmox-post-deploy.sh
# After reboot, SSH again
sudo bash install-proxmox-step2.sh
```

### Option C: Using Ansible (recommended for multiple hosts)

See the example Ansible playbook in `ansible/install-proxmox.yml`

## Verification

After installation completes:

1. **Access web interface**: `https://<deployed-ip>:8006`
2. **Login as**: `root` with the password set during MAAS deployment
3. **Verify Proxmox version**: Check the dashboard shows "Proxmox VE 9.1"

## Why Post-Deployment?

Proxmox VE requires:
- A proper hostname that resolves to a non-loopback IP address
- Functional network configuration
- Postfix mail server configured with correct hostname

These conditions don't exist during the packer build but are automatically configured by MAAS during deployment. Installing Proxmox post-deployment ensures all dependencies are properly satisfied.

## Troubleshooting

### "Hostname is not properly configured" error

Check that `/etc/hosts` has an entry like:
```
192.168.x.x    hostname.domain hostname
```

And NOT:
```
127.0.1.1    hostname
```

MAAS should configure this automatically. If not, check the MAAS preseed configuration.

### Subscription warning

The "pve-no-subscription" repository shows a warning in the web UI. This is expected for non-commercial installations and can be safely ignored, or you can purchase a subscription key from Proxmox.
