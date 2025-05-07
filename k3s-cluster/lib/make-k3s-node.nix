# ./k3s-cluster/lib/make-k3s-node.nix
{ lib, pkgs }:
{
  hostname ? "nixos-k3s-node", # Default, should be overridden
  system ? "x86_64-linux",
  role ? "worker", # "control" or "worker"
  location ? "hetzner", # "hetzner" or "local"

  # Path to a specific hardware-configuration.nix.
  # For nixos-everywhere.sh deployments, this is NOT used, as the script generates one.
  # Useful for local VMs or specific bare-metal with a known hardware config.
  hardwareConfigPath ? null,

  # --- Core Arguments passed via specialArgs to all modules ---
  # These define the node's operational parameters.
  k3sControlPlaneAddr ? "10.0.0.2", # Default, should be overridden by actual IP/DNS
  nodeSecretsProvider ? "infisical", # "infisical" (default) or "sops"

  # Only relevant if nodeSecretsProvider = "sops" for K3S/Tailscale bootstrap
  sopsSecretsFile ? ../secrets.nix, # Default path to your sops secrets definitions

  # Only relevant if nodeSecretsProvider = "infisical" for K3S/Tailscale bootstrap
  # This entire structure is passed as specialArgs.infisicalBootstrap
  # Example structure: { clientIdFileContent = "...", clientSecretFileContent = "...", infisicalAddress = "..." }
  infisicalBootstrapCredentials ? { },

  # For control plane clustering
  isFirstControlPlane ? (role == "control"), # Default true if role is control, pass false for subsequent CP nodes

  # Hetzner specific interface names (can be overridden)
  hetznerPublicInterface ? "eth0",
  hetznerPrivateInterface ? "ens10",

  # General NixOS settings (can be overridden by more specific modules)
  adminUsername ? (builtins.getEnv "ADMIN_USERNAME"),
  adminSshPublicKey ? (builtins.getEnv "ADMIN_SSH_PUBLIC_KEY"),
  nixosStateVersion ? (builtins.getEnv "STATE_VERSION_INIT"), # From nixos-everywhere.sh
  targetImageDiskDevice ? "/dev/sda", # For disko when building images
  targetImageSwapSize ? "4G", # For disko when building images

  extraModules ? [ ], # For one-off module additions
  finalExtraConfig ? { }, # For ad-hoc NixOS option overrides at the very end
}:

let
  commonConfigModule = ../common.nix;
  baseServerProfileModule = ../profiles/base-server.nix;

  roleModule =
    if role == "control" then
      ../roles/k3s-control.nix
    else if role == "worker" then
      ../roles/k3s-worker.nix
    else if role == "none" then
      { } # No K3s role, e.g. for a utility VM
    else
      throw "Invalid role: ${role}. Must be 'control', 'worker', or 'none'.";

  locationModule =
    if location == "hetzner" then
      ../locations/hetzner.nix
    else if location == "local" then
      ../locations/local.nix
    else
      { }; # No specific location module if not hetzner/local

in
lib.nixosSystem {
  inherit system;

  specialArgs =
    {
      # Make all input parameters available as specialArgs for modules
      inherit
        hostname
        role
        location
        k3sControlPlaneAddr
        nodeSecretsProvider
        isFirstControlPlane
        hetznerPublicInterface
        hetznerPrivateInterface
        adminUsername
        adminSshPublicKey
        nixosStateVersion
        targetImageDiskDevice
        targetImageSwapSize
        ;
      # Pass the infisicalBootstrapCredentials structure directly if provided
    }
    // (
      if infisicalBootstrapCredentials != { } then
        { infisicalBootstrap = infisicalBootstrapCredentials; }
      else
        { }
    )
    // (finalExtraConfig.specialArgs or { }); # Allow merging from finalExtraConfig

  modules =
    [
      commonConfigModule # Applied first
      baseServerProfileModule # Applied after common
      locationModule # Applied after base profile
      roleModule # Applied after location

      # Import hardwareConfigPath only if it's a valid path string.
      # For nixos-everywhere.sh, its generated hardware-config is imported by the bridging config.
      (lib.mkIf (
        hardwareConfigPath != null && builtins.typeOf hardwareConfigPath == "string"
      ) hardwareConfigPath)

      # Ensure hostname is set (can also be done in commonConfig via specialArgs.hostname)
      (
        { config, ... }:
        {
          networking.hostName = hostname;
        }
      )

      # Conditionally import sops-nix module and the user's sops secrets definition
      # if secrets are managed by sops for this node.
      (lib.mkIf (nodeSecretsProvider == "sops") (inputs.sops-nix.nixosModules.sops)) # Assuming 'inputs' is in scope or passed via pkgs
      (lib.mkIf (nodeSecretsProvider == "sops" && sopsSecretsFile != null) sopsSecretsFile)

    ]
    ++ extraModules
    ++ [
      finalExtraConfig # Apply any final ad-hoc config last
    ];
}
