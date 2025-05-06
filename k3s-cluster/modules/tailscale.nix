# k3s-cluster/modules/tailscale.nix
# Major Update: This module now just ensures the Tailscale package is installed
# K3s will manage the Tailscale connection via --vpn-auth flag
{ config, lib, pkgs, ... }: {
  # Just install the Tailscale package
  environment.systemPackages = [ pkgs.tailscale ];
  
  # Allow Tailscale traffic through NixOS firewall
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 41641 ];
  };
  
  # Note: We no longer need to configure services.tailscale.enable = true
  # or authKeyFile via sops-nix, as K3s manages Tailscale connection
}