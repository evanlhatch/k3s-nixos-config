{ config, lib, pkgs, specialArgs, ... }:

let
  # Get SSH public key from environment
  sshPublicKey = builtins.getEnv "ADMIN_SSH_PUBLIC_KEY";
in
{
  time.timeZone = "Etc/UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ]; # Add docker group if needed
    openssh.authorizedKeys.keys = [ sshPublicKey ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    vim
    tmux
    jq
  ];
  
  nixpkgs.config.allowUnfree = true;
}