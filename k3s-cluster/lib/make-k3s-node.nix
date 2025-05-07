# ./k3s-cluster/lib/make-k3s-node.nix
{
  lib,
  pkgs,
  # Parameters for makeK3sNode
  hostname ? "nixos-k3s-node",
  system ? "x86_64-linux",
  role ? "worker",
  location ? "hetzner",
  hardwareConfigPath ? null,
  k3sControlPlaneAddr,
  nodeSecretsProvider ? "infisical", # Default to Infisical
  sopsSecretsFile ? null, # Path to the secrets.nix file if provider is "sops"
  infisicalBootstrapCredentials ? { }, # Credentials for Infisical agent
  isFirstControlPlane ? (role == "control"), # Default for control plane role
  hetznerPublicInterface ? "eth0",
  hetznerPrivateInterface ? "ens10",
  adminUsername ? "nixos",
  adminSshPublicKey ? "ssh-ed25519 AAA...", # Provide a valid fallback or ensure it's always passed
  nixosStateVersion ? "24.11",
  targetImageDiskDevice ? "/dev/sda",
  targetImageSwapSize ? "4G",

  # Modules passed from Flake's inputs
  sopsNixModule ? null, # This will be inputs.sops-nix.nixosModules.sops
  diskoModule ? null, # This will be inputs.disko.nixosModules.disko

  extraModules ? [ ],
  finalExtraConfig ? { },
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
      ({ ... }: { }) # No K3s role, but provide a valid module
    else
      throw "Invalid role: ${role}";

  locationModule =
    if location == "hetzner" then
      ../locations/hetzner.nix
    else if location == "local" then
      ../locations/local.nix
    else
      ({ ... }: { }); # Provide a valid empty module
in
lib.nixosSystem {
  inherit system;

  specialArgs =
    {
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
      # Add modulesPath for NixOS modules that need it
      modulesPath = "${toString pkgs.path}/nixos/modules";
    }
    // (
      if infisicalBootstrapCredentials != { } && nodeSecretsProvider == "infisical" then
        { infisicalBootstrap = infisicalBootstrapCredentials; }
      else
        { }
    );

  modules =
    [
      commonConfigModule
      baseServerProfileModule
      (lib.mkIf (location == "hetzner" || location == "local") locationModule)
      (lib.mkIf (role == "control" || role == "worker") roleModule) # This needs to use specialArgs.nodeSecretsProvider

      (lib.mkIf (
        hardwareConfigPath != null && builtins.typeOf hardwareConfigPath == "string"
      ) hardwareConfigPath)

      (
        { config, ... }:
        {
          networking.hostName = hostname;
        }
      ) # Explicitly set hostname

      # Conditionally import sops-nix module and the user's sops secrets definition
      (lib.mkIf (nodeSecretsProvider == "sops" && sopsNixModule != null) sopsNixModule)
      (lib.mkIf (nodeSecretsProvider == "sops" && sopsSecretsFile != null) sopsSecretsFile)

      # Example for disko, if image configs use makeK3sNode and want disko this way:
      # (lib.mkIf (/* some condition, e.g. specialArgs.useDisko */ && diskoModule != null) diskoModule)
      # (lib.mkIf (/* some condition */ && specialArgs.diskoConfigFile != null) specialArgs.diskoConfigFile)

    ]
    ++ (if extraModules != null then extraModules else [])
    ++ (if finalExtraConfig != null && finalExtraConfig != { } then [ finalExtraConfig ] else [ ]);
}
