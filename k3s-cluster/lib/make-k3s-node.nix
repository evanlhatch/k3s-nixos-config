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
let
  # Create a simple specialArgs set with all the parameters
  specialArgsSet = {
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
  };

  # Add infisicalBootstrap if needed
  specialArgsWithInfisical =
    if infisicalBootstrapCredentials != { } && nodeSecretsProvider == "infisical"
    then specialArgsSet // { infisicalBootstrap = infisicalBootstrapCredentials; }
    else specialArgsSet;
in

lib.nixosSystem {
  inherit system;
  specialArgs = specialArgsWithInfisical;

  # Create a list of base modules that are always included
  baseModules = [
    commonConfigModule
    baseServerProfileModule
    { networking.hostName = hostname; } # Explicitly set hostname
  ];

  # Add location module if applicable
  locationModules = if (location == "hetzner" || location == "local")
                    then [ locationModule ]
                    else [];

  # Add role module if applicable
  roleModules = if (role == "control" || role == "worker")
                then [ roleModule ]
                else [];

  # Add hardware config if provided
  hardwareModules = if (hardwareConfigPath != null && builtins.typeOf hardwareConfigPath == "string")
                    then [ hardwareConfigPath ]
                    else [];

  # Add sops modules if applicable
  sopsModules = if (nodeSecretsProvider == "sops")
                then (if sopsNixModule != null then [ sopsNixModule ] else []) ++
                     (if sopsSecretsFile != null then [ sopsSecretsFile ] else [])
                else [];

  # Add finalExtraConfig if it's not empty
  finalModules = if finalExtraConfig != { }
                 then [ finalExtraConfig ]
                 else [];

  # Combine all modules
  allModules = baseModules ++ locationModules ++ roleModules ++
               hardwareModules ++ sopsModules ++ extraModules ++ finalModules;
in

lib.nixosSystem {
  inherit system;
  specialArgs = specialArgsWithInfisical;
  modules = allModules;
}
