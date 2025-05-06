#!/bin/bash
set -eux

echo "Starting NixOS direct installation on Hetzner Cloud..."

# Ensure we have all required packages
echo "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl wget git parted dosfstools gnupg2 sudo

# Clean up any existing Nix installation
echo "Cleaning up any existing Nix installation..."
systemctl stop nix-daemon.socket 2>/dev/null || true
systemctl stop nix-daemon.service 2>/dev/null || true
systemctl disable nix-daemon.socket 2>/dev/null || true
systemctl disable nix-daemon.service 2>/dev/null || true
systemctl daemon-reload || true

# Restore original bash.bashrc if backup exists
if [ -f /etc/bash.bashrc.backup-before-nix ]; then
  cp /etc/bash.bashrc.backup-before-nix /etc/bash.bashrc || true
fi

# Remove all Nix-related files
rm -rf /etc/nix /nix /root/.nix-profile /root/.nix-defexpr /root/.nix-channels /root/.local/state/nix /root/.cache/nix || true
rm -f /etc/profile.d/nix.sh || true

# Partition the disk
echo "Partitioning disk..."
parted -s /dev/sda -- mklabel gpt
parted -s /dev/sda -- mkpart ESP fat32 1MB 512MB
parted -s /dev/sda -- set 1 esp on
parted -s /dev/sda -- mkpart swap linux-swap 512MB 8.5GB
parted -s /dev/sda -- mkpart root ext4 8.5GB 100%

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F 32 /dev/sda1
mkswap /dev/sda2
mkfs.ext4 /dev/sda3

# Wait for the kernel to recognize the new partitions
echo "Waiting for partitions to be recognized..."
sleep 5
sync
udevadm trigger
udevadm settle

# Verify partitions
echo "Verifying partitions..."
lsblk -o NAME,UUID,FSTYPE
if ! blkid /dev/sda3 -o value -s TYPE | grep -q ext4; then
    echo "Error: /dev/sda3 not found or not ext4"
    exit 1
fi

# Mount partitions using device paths directly
echo "Mounting partitions..."
mount /dev/sda3 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
swapon /dev/sda2

# Verify mounts
echo "Verifying mounts..."
mount | grep /mnt
mount | grep /mnt/boot
swapon --show | grep /dev/sda2

# Download NixOS installation ISO and extract the tools directly
echo "Downloading NixOS ISO..."
mkdir -p /tmp/nixos-tools
cd /tmp/nixos-tools

# Install squashfs-tools if not already installed
apt-get install -y squashfs-tools

# Download the minimal NixOS ISO
wget -q https://channels.nixos.org/nixos-24.11/latest-nixos-minimal-x86_64-linux.iso -O nixos.iso

# Mount the ISO
mkdir -p /tmp/nixos-iso
mount -o loop nixos.iso /tmp/nixos-iso

# Extract the squashfs filesystem to get the tools
echo "Extracting NixOS tools..."
mkdir -p /tmp/nixos-extract
unsquashfs -n -f -d /tmp/nixos-extract /tmp/nixos-iso/nix-store.squashfs

# Find the nixos-install and nixos-generate-config tools
echo "Finding NixOS tools..."
NIXOS_INSTALL=$(find /tmp/nixos-extract -name nixos-install -type f -executable | head -n1)
NIXOS_GENERATE_CONFIG=$(find /tmp/nixos-extract -name nixos-generate-config -type f -executable | head -n1)

if [ -z "$NIXOS_INSTALL" ] || [ -z "$NIXOS_GENERATE_CONFIG" ]; then
  echo "Error: Could not find NixOS installation tools"
  exit 1
fi

echo "Using nixos-install: $NIXOS_INSTALL"
echo "Using nixos-generate-config: $NIXOS_GENERATE_CONFIG"

# Copy the tools to a location in PATH
mkdir -p /usr/local/bin
cp $NIXOS_INSTALL $NIXOS_GENERATE_CONFIG /usr/local/bin/
chmod +x /usr/local/bin/nixos-install /usr/local/bin/nixos-generate-config

# Set the PATH to include our tools
export PATH="/usr/local/bin:$PATH"

# Create required users and groups for Nix
echo "Setting up Nix users and groups..."
groupadd -r nixbld
for i in $(seq 1 10); do
  useradd -r -M -N -g nixbld -d /var/empty -s /sbin/nologin "nixbld$i"
done

# Create /etc/nix/nix.conf with experimental features enabled
mkdir -p /etc/nix
cat > /etc/nix/nix.conf << EOF
experimental-features = nix-command flakes
EOF

# Download nixpkgs
echo "Downloading nixpkgs..."
mkdir -p /root/nixpkgs
cd /root
curl -L https://github.com/NixOS/nixpkgs/archive/refs/tags/branch-off-24.11.tar.gz -o nixpkgs.tar.gz
tar xf nixpkgs.tar.gz --strip-components=1 -C nixpkgs
export NIX_PATH=nixpkgs=/root/nixpkgs
echo "Downloading minimal NixOS ISO for tools..."
mkdir -p /tmp/nixos-tools
cd /tmp/nixos-tools
wget -q https://channels.nixos.org/nixos-24.11/latest-nixos-minimal-x86_64-linux.iso -O nixos.iso

# Mount the ISO
mkdir -p /tmp/nixos-iso
mount -o loop nixos.iso /tmp/nixos-iso

# Extract the squashfs filesystem to get the tools
mkdir -p /tmp/nixos-extract
unsquashfs -n -f -d /tmp/nixos-extract /tmp/nixos-iso/nix-store.squashfs

# Find the nixos-install and nixos-generate-config tools
NIXOS_INSTALL=$(find /tmp/nixos-extract -name nixos-install -type f -executable | head -n1)
NIXOS_GENERATE_CONFIG=$(find /tmp/nixos-extract -name nixos-generate-config -type f -executable | head -n1)

if [ -z "$NIXOS_INSTALL" ] || [ -z "$NIXOS_GENERATE_CONFIG" ]; then
  echo "Error: Could not find NixOS installation tools"
  exit 1
fi

echo "Using nixos-install: $NIXOS_INSTALL"
echo "Using nixos-generate-config: $NIXOS_GENERATE_CONFIG"

# Copy the tools to a location in PATH
mkdir -p /usr/local/bin
cp $NIXOS_INSTALL $NIXOS_GENERATE_CONFIG /usr/local/bin/
chmod +x /usr/local/bin/nixos-install /usr/local/bin/nixos-generate-config

# Set the PATH to include our tools
export PATH="/usr/local/bin:$PATH"

# Download nixpkgs
echo "Downloading nixpkgs..."
mkdir -p /root/nixpkgs
cd /root
curl -L https://github.com/NixOS/nixpkgs/archive/refs/tags/branch-off-24.11.tar.gz -o nixpkgs.tar.gz
tar xf nixpkgs.tar.gz --strip-components=1 -C nixpkgs
export NIX_PATH=nixpkgs=/root/nixpkgs

# Create the necessary directories for NixOS installation
mkdir -p /mnt/etc/nixos

# Generate hardware configuration
echo "Generating hardware configuration..."
nixos-generate-config --root /mnt

# Create configuration.nix
cat > /mnt/etc/nixos/configuration.nix << 'EOF'
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-k3s";
  networking.networkmanager.enable = true;

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Enable cloud-init
  services.cloud-init.enable = true;

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    kubectl
  ];

  # Set up user
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRoa3k+/c6nIFLQHo4XYROMFzRx8j+MoRcrt0FmH8/BxAPpDH55SFMM2CY46LEH14M/+W0baSHhQjX//PEL93P5iN3uIlf9+I6aQr8Fi4F3c5susHqGmIWGTIEridVhEqzOQKDv/S9L1K3sDbjMYBXFyYo95dTIzYaJoxFsBF6cwxuscnKM/vb3eidYctZ61GukFvIkUTMRhO2KsEbc4RCslpTCdYgu7nkHiyCJZW7e37bRJ4AJwnjjX5ObP648wQ2UA0PpYLBUr0JQK6iQTAjwIHLNJheHYaGRf4IHP6sp9YSeY/IqnKMd4aEQd64Too1wMIsWyez9SIwgcH4fyNT"
    ];
  };

  # Also add SSH key to root user
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRoa3k+/c6nIFLQHo4XYROMFzRx8j+MoRcrt0FmH8/BxAPpDH55SFMM2CY46LEH14M/+W0baSHhQjX//PEL93P5iN3uIlf9+I6aQr8Fi4F3c5susHqGmIWGTIEridVhEqzOQKDv/S9L1K3sDbjMYBXFyYo95dTIzYaJoxFsBF6cwxuscnKM/vb3eidYctZ61GukFvIkUTMRhO2KsEbc4RCslpTCdYgu7nkHiyCJZW7e37bRJ4AJwnjjX5ObP648wQ2UA0PpYLBUr0JQK6iQTAjwIHLNJheHYaGRf4IHP6sp9YSeY/IqnKMd4aEQd64Too1wMIsWyez9SIwgcH4fyNT"
  ];

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}
EOF

# Create a flake.nix file
cat > /mnt/etc/nixos/flake.nix << 'EOF'
{
  description = "NixOS K3s configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
      ];
    };
  };
}
EOF

# Install NixOS
echo "Installing NixOS..."
# Use --no-root-passwd to skip setting the root password
# Use --option substituters to specify the binary cache
nixos-install --root /mnt --no-root-passwd --option substituters "https://cache.nixos.org"

# Clean up
echo "Cleaning up..."
# Unmount the ISO
umount /tmp/nixos-iso || true

# Clean up temporary files
rm -rf /tmp/nix-install
rm -rf /tmp/nixos-tools
rm -rf /tmp/nixos-iso
rm -rf /tmp/nixos-extract
rm -rf /root/nixpkgs /root/nixpkgs.tar.gz
rm -rf /mnt/tmp/* # Clean up temporary files on the target filesystem

# Unmount everything
umount /mnt/boot || true
umount /mnt || true
swapoff /dev/sda2 || true

echo "NixOS installation completed successfully!"