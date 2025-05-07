# ./k3s-cluster/modules/disko-hetzner.nix
# This module defines a disk layout specifically for building Hetzner disk images
# (e.g., using NixOS's make-disk-image.nix functions).
# It is NOT used by nixos-everywhere.sh for installing onto the existing root FS.
{
  config,
  lib,
  pkgs,
  specialArgs ? { },
  ...
}:
{
  disko.devices = {
    disk = {
      mainDisk = {
        # Name for this disk configuration (e.g. "sda" or "nvme0n1")
        device = specialArgs.targetImageDiskDevice or "/dev/sda"; # Allow override via Flake for image build
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              name = "ESP";
              size = "512M";
              type = "EF00"; # EFI System Partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            swap = {
              name = "SWAP";
              size = specialArgs.targetImageSwapSize or "4G"; # Allow override
              content = {
                type = "swap";
              };
            };
            root = {
              name = "NIXOS_ROOT";
              size = "100%"; # Use remaining space
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
