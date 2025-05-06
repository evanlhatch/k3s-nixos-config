#!/bin/bash
set -eux

echo "Starting NixOS installation on Hetzner Cloud..."

# Ensure we have all required packages
echo "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y curl wget git squashfs-tools parted dosfstools gnupg2

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
mkfs.fat -F 32 -n boot /dev/sda1
mkswap -L swap /dev/sda2
mkfs.ext4 -L nixos /dev/sda3

# Wait for the kernel to recognize the new partitions and labels
echo "Waiting for partitions to be recognized..."
sleep 5
sync
udevadm trigger
udevadm settle

# Verify partitions
echo "Verifying partitions..."
lsblk -o NAME,LABEL,UUID,FSTYPE
# Add a check to ensure /dev/sda3 exists and has the correct filesystem
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


# Download NixOS ISO
echo "Downloading NixOS ISO..."
wget https://channels.nixos.org/nixos-24.11/latest-nixos-minimal-$(uname -m)-linux.iso -O nixos.iso

# Mount the ISO
echo "Mounting NixOS ISO..."
mkdir -p nixos
mount -o loop nixos.iso nixos

# Create a temporary directory for extraction on the target filesystem
echo "Creating temporary directory for extraction on target filesystem..."
mkdir -p /mnt/tmp/nix-store-extract

# Extract the squashfs filesystem with options to avoid issues
echo "Extracting NixOS tools..."
unsquashfs -no-progress -f -processors 1 -d /mnt/tmp/nix-store-extract nixos/nix-store.squashfs

# Create /nix directory on the target system
echo "Setting up Nix store on target system..."
mkdir -p /mnt/nix/store

# Copy the extracted store to the target system
echo "Copying Nix store to target system..."
cp -a /mnt/tmp/nix-store-extract/* /mnt/nix/store/

# Find the necessary NixOS tools within the extracted store on the target filesystem
echo "Finding NixOS tools..."
NIXOS_INSTALL=$(find /mnt/tmp/nix-store-extract -path '*-nixos-install/bin/nixos-install')
NIX_INSTANTIATE=$(find /mnt/tmp/nix-store-extract -path '*-nix-*/bin/nix-instantiate')
NIXOS_GENERATE_CONFIG=$(find /mnt/tmp/nix-store-extract -path '*-nixos-generate-config/bin/nixos-generate-config')
# Export PATH relative to the mounted filesystem for the next steps
export PATH="/mnt$(dirname $NIXOS_INSTALL):/mnt$(dirname $NIX_INSTANTIATE):/mnt$(dirname $NIXOS_GENERATE_CONFIG):$PATH"

# Create required users and groups on the target system
echo "Setting up Nix users and groups..."
chroot /mnt groupadd --system nixbld || true
chroot /mnt useradd --system --home-dir /var/empty --shell $(which nologin) -g nixbld -G nixbld nixbld0 || true

# Download nixpkgs to the target system
echo "Downloading nixpkgs..."
wget https://github.com/NixOS/nixpkgs/archive/refs/tags/branch-off-24.11.zip -O /mnt/tmp/nixpkgs.zip
chroot /mnt unzip /tmp/nixpkgs.zip -d /tmp
chroot /mnt mv /tmp/nixpkgs-* /nixpkgs
export NIX_PATH=nixpkgs=/nixpkgs # Set NIX_PATH for the chrooted environment

# Generate NixOS configuration
echo "Generating NixOS configuration..."
chroot /mnt nixos-generate-config --root /mnt

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
chroot /mnt nixos-install --no-root-passwd

# Clean up
echo "Cleaning up..."
rm -rf /mnt/root/.nix-profile
rm -rf /mnt/root/.nix-defexpr
rm -rf /mnt/root/.nix-channels
rm -rf /mnt/tmp/* # Clean up temporary files on the target filesystem

# Unmount everything
umount /mnt/boot || true
umount /mnt || true
swapoff /dev/sda2 || true
umount nixos || true

# Clean up temporary files and mounts
rm -rf nixos nixos.iso nixpkgs.zip

echo "NixOS installation completed successfully!"