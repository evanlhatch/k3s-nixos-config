{ config, lib, pkgs, ... }:

{
  imports = [
    ../../../k3s-cluster/common.nix
    ../../../k3s-cluster/profiles/base-server.nix
    ../../../k3s-cluster/locations/hetzner.nix
    ../../../k3s-cluster/roles/k3s-control.nix
    ../../../k3s-cluster/modules/infisical-agent.nix
    ../../../k3s-cluster/modules/tailscale.nix
  ];
  
  # Set basic configuration
  networking.hostName = "k3s-control-tmpl";
  time.timeZone = "Etc/UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Required file system configuration
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  
  # Basic boot configuration
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  
  # Set system state version
  system.stateVersion = "24.11";
}