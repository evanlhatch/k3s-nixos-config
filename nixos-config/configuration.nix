{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
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
      # SSH key will be added by the installation script
    ];
  };
  
  # Also add SSH key to root user
  users.users.root.openssh.authorizedKeys.keys = [
    # SSH key will be added by the installation script
  ];
  
  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}