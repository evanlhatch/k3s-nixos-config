{ lib, pkgs }:
{ 
  hostname ? "nixos",
  system ? "x86_64-linux",
  role ? "worker", # "control" or "worker"
  location ? "hetzner", # "hetzner" or "local"
  hardwareConfig ? null, # Path to hardware-configuration.nix for local machines
  k3sControlPlaneAddr ? "10.0.0.2", # IP of the control plane node
  k3sToken ? "", # K3s cluster token
  tailscaleAuthKey ? "", # Tailscale auth key
  extraModules ? [], # Additional NixOS modules to include
  extraConfig ? {} # Additional configuration to merge
}:

let
  # Import common configuration
  commonConfig = ../common.nix;

  # Import role-specific configuration
  roleConfig = if role == "control" then ../roles/k3s-control.nix
              else if role == "worker" then ../roles/k3s-worker.nix
              else throw "Invalid role: ${role}. Must be 'control' or 'worker'";

  # Import location-specific configuration
  locationConfig = if location == "hetzner" then ../locations/hetzner.nix
                  else if location == "local" then ../locations/local.nix
                  else throw "Invalid location: ${location}. Must be 'hetzner' or 'local'";

  # Import base server profile
  baseServerConfig = ../profiles/base-server.nix;

  # Import hardware configuration if provided (for local machines)
  hardwareConfigModule = if hardwareConfig != null 
                        then hardwareConfig
                        else {};

  # Combine all configurations
  combinedConfig = {
    networking.hostName = hostname;
    
    # Pass special arguments to modules
    _module.args = {
      inherit k3sControlPlaneAddr k3sToken tailscaleAuthKey;
      nodeRole = role;
      nodeLocation = location;
    };
  };

in
# Return a NixOS system configuration directly
lib.nixosSystem {
  inherit system;
  
  modules = [
    commonConfig
    baseServerConfig
    roleConfig
    locationConfig
    (if hardwareConfig != null then hardwareConfig else {})
    combinedConfig
    extraConfig
  ] ++ extraModules;
}