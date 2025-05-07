# /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/flake.nix
{
  description = "NixOS K3s Cluster on Hetzner Cloud with FluxCD";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or your preferred nixos-24.11
    flake-utils.url = "github:numtide/flake-utils";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, sops-nix, deploy-rs, disko, ... }@inputs: # Make all inputs accessible
    let
      # Import the make-k3s-node function and pass necessary Flake inputs to it
      makeK3sNode = system: args:
        let
          # Create a merged set of arguments with defaults from commonNodeArgumentsFromEnv
          mergedArgs = {
            inherit (nixpkgs) lib;
            pkgs = nixpkgs.legacyPackages.${system};
            # Pass the sops-nix module itself, not the whole inputs attrset
            sopsNixModule = inputs.sops-nix.nixosModules.sops;
            # Pass the disko module if makeK3sNode needs to conditionally import it
            diskoModule = disko.nixosModules.disko;
            # Pass common arguments
            k3sControlPlaneAddr = commonNodeArgumentsFromEnv.k3sControlPlaneAddr;
            adminUsername = commonNodeArgumentsFromEnv.adminUsername;
            adminSshPublicKey = commonNodeArgumentsFromEnv.adminSshPublicKey;
            nixosStateVersion = commonNodeArgumentsFromEnv.nixosStateVersion;
            hetznerPublicInterface = commonNodeArgumentsFromEnv.hetznerPublicInterface;
            hetznerPrivateInterface = commonNodeArgumentsFromEnv.hetznerPrivateInterface;
            targetImageDiskDevice = commonNodeArgumentsFromEnv.targetImageDiskDevice;
            targetImageSwapSize = commonNodeArgumentsFromEnv.targetImageSwapSize;
            # Default empty values for optional parameters
            extraModules = [];
            finalExtraConfig = {};
          } // args;
        in
          import ./k3s-cluster/lib/make-k3s-node.nix mergedArgs;

      # Common arguments (sourced from environment for local builds, or defaults)
      # Helper function for environment variables with defaults
      getEnv = name: default: let val = builtins.getEnv name; in if val == "" then default else val;
      
      commonNodeArgumentsFromEnv = {
        k3sControlPlaneAddr = getEnv "K3S_CONTROL_PLANE_ADDR" "hetzner-control-01.cinnamon-galaxy.ts.net"; # Use Tailscale FQDN
        adminUsername = getEnv "ADMIN_USERNAME" "nixos";
        adminSshPublicKey = getEnv "ADMIN_SSH_PUBLIC_KEY" "YOUR_FALLBACK_SSH_PUBLIC_KEY_HERE_AS_A_STRING"; # Ensure this is a valid key string
        nixosStateVersion = getEnv "NIXOS_STATE_VERSION" "24.11";
        hetznerPublicInterface = getEnv "HETZNER_PUBLIC_IFACE" "eth0";
        hetznerPrivateInterface = getEnv "HETZNER_PRIVATE_IFACE" "ens10";
        targetImageDiskDevice = getEnv "TARGET_IMAGE_DISK_DEVICE" "/dev/sda";
        targetImageSwapSize = getEnv "TARGET_IMAGE_SWAP_SIZE" "4G";
      };

      # Infisical bootstrap credentials for templates/images
      infisicalBootstrapForTemplatesAndImages = {
        infisicalBootstrap = { # This whole structure is passed as specialArgs.infisicalBootstrap
          clientIdFileContent = getEnv "INFISICAL_CLIENT_ID_FOR_FLAKE" "";
          clientSecretFileContent = getEnv "INFISICAL_CLIENT_SECRET_FOR_FLAKE" "";
          infisicalAddress = getEnv "INFISICAL_ADDRESS_FOR_FLAKE" "";
        };
        nodeSecretsProvider = "infisical"; # Signal to use Infisical
      };

    in
    {
      nixosConfigurations = {
        # === TEMPLATES FOR nixos-everywhere.sh (USE INFISICAL FOR BOOTSTRAP SECRETS) ===
        "hetznerK3sWorkerTemplate" = makeK3sNode "x86_64-linux" {
          hostname = "k3s-worker-tmpl";
          role = "worker";
          location = "hetzner";
          nodeSecretsProvider = "infisical";
          infisicalBootstrapCredentials = infisicalBootstrapForTemplatesAndImages.infisicalBootstrap;
          extraModules = [
            ./k3s-cluster/modules/infisical-agent.nix
            ./k3s-cluster/modules/tailscale.nix
            # NO sops-nix module or secrets.nix here for K3s/Tailscale bootstrap
            # NO disko modules for root disk here
          ];
        };

        "hetznerK3sControlTemplate" = makeK3sNode "x86_64-linux" {
          hostname = "k3s-control-tmpl";
          role = "control";
          location = "hetzner";
          isFirstControlPlane = true;
          nodeSecretsProvider = "infisical";
          infisicalBootstrapCredentials = infisicalBootstrapForTemplatesAndImages.infisicalBootstrap;
          extraModules = [
            ./k3s-cluster/modules/infisical-agent.nix
            ./k3s-cluster/modules/tailscale.nix
          ];
        };

        # === NODES FOR DEPLOY-RS (Can use SOPS-NIX) ===
        "hetzner-control-01" = makeK3sNode "x86_64-linux" {
          hostname = "hetzner-control-01";
          role = "control";
          location = "hetzner";
          nodeSecretsProvider = "sops"; # This node uses SOPS for K3s/Tailscale secrets
          sopsSecretsFile = ./k3s-cluster/secrets.nix; # Path to sops secret definitions
          isFirstControlPlane = true;
          # hardwareConfigPath can be a specific file for this node if not using disko for it
          # hardwareConfigPath = ./k3s-cluster/hardware-configs/hetzner-control-01.nix;
          # If this node also needs disko for its setup (e.g. if deploy-rs handles partitioning)
          extraModules = [
            # disko.nixosModules.disko
            # ./k3s-cluster/modules/disko-hetzner.nix
          ];
        };

        "hetzner-worker-static-01" = makeK3sNode "x86_64-linux" {
          hostname = "hetzner-worker-static-01";
          role = "worker";
          location = "hetzner";
          nodeSecretsProvider = "sops";
          sopsSecretsFile = ./k3s-cluster/secrets.nix;
          extraModules = [];
        };

        # === CONFIGURATIONS FOR BUILDING STANDALONE DISK IMAGES (Uses Infisical + Disko) ===
        "k3sWorkerImageConfig" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = commonNodeArgumentsFromEnv // infisicalBootstrapForTemplatesAndImages // {
            hostname = "k3s-worker-img";
            role = "worker";
            location = "hetzner";
            # Ensure disko-hetzner.nix uses specialArgs for diskDevice and swapSize if needed
          };
          modules = [
            ./k3s-cluster/common.nix
            ./k3s-cluster/profiles/base-server.nix
            ./k3s-cluster/locations/hetzner.nix
            ./k3s-cluster/roles/k3s-worker.nix    # Must be Infisical-aware via specialArgs.nodeSecretsProvider
            ./k3s-cluster/modules/infisical-agent.nix # Configured by specialArgs.infisicalBootstrap
            ./k3s-cluster/modules/tailscale.nix
            disko.nixosModules.disko                 # Disko module for partitioning
            ./k3s-cluster/modules/disko-hetzner.nix  # Your specific Disko layout for images
            { system.stateVersion = commonNodeArgumentsFromEnv.nixosStateVersion; }
            
            # Add dummy filesystem and boot loader configuration for flake check
            { lib, ... }: {
              # Dummy filesystem configuration for flake check
              fileSystems."/" = lib.mkForce {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
              };
              
              # Dummy boot loader configuration for flake check
              boot.loader.grub = lib.mkForce {
                enable = true;
                devices = [ "/dev/sda" ];
              };
            }
          ];
        };
        # ... (similar for k3sControlImageConfig) ...

        # Example for local installer ISO
        "localInstallerIsoConfig" = makeK3sNode "x86_64-linux" {
           hostname = "nixos-installer";
           role = "none";
           location = "local";
           nodeSecretsProvider = "none"; # No bootstrap secrets for a generic installer
           hardwareConfigPath = "${nixpkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix";
           extraModules = [
             { environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [ git vim parted gptfdisk disko ]; }
             { services.openssh.settings.PermitRootLogin = "yes"; }
             { users.users.root.openssh.authorizedKeys.keys = [ commonNodeArgumentsFromEnv.adminSshPublicKey ]; }
           ];
         };
      }; # End nixosConfigurations

      deploy.nodes = {
        "hetzner-control-01" = {
          hostname = commonNodeArgumentsFromEnv.k3sControlPlaneAddr; # Use its Tailscale/known hostname
          sshUser = commonNodeArgumentsFromEnv.adminUsername;
          fastConnection = true;
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.${nixpkgs.system}.activate.nixos self.nixosConfigurations."hetzner-control-01";
          };
          sops.keyFile = "${getEnv "HOME" "~"}/.config/sops/age/keys.txt";
        };
        # Add "hetzner-worker-static-01" similarly
      };

      packages = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          buildDiskImage = name: nixosConfigName: format: diskSize: pkgs.callPackage "${nixpkgs}/nixos/lib/make-disk-image.nix" {
            inherit name format diskSize;
            config = self.nixosConfigurations."${nixosConfigName}".config;
          };
        in
        {
          hetznerK3sWorkerRawImage = buildDiskImage "hetzner-k3s-worker-image" "k3sWorkerImageConfig" "raw" "10G";
          hetznerK3sControlRawImage = buildDiskImage "hetzner-k3s-control-image" "k3sControlImageConfig" "raw" "10G";
          k3sInstallerIso = self.nixosConfigurations.localInstallerIsoConfig.config.system.build.isoImage;
        });

      devShells = flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              git curl wget jq yq
              nixpkgs-fmt
              hcloud kubectl kubernetes-helm fluxcd
              inputs.deploy-rs.packages.${system}.deploy-rs
              inputs.sops-nix.packages.${system}.sops
              just
              gh
              tailscale
            ];

            shellHook = ''
              echo "--- NixOS K3s Hetzner Dev Environment ---"
              echo "Ensure your .env file is populated and 'direnv allow .' has been run."
              echo "Available 'just' commands:"
              just -l 2>/dev/null || echo "just not found or no Justfile present"
              echo "---------------------------------------"
              # Export ENV VARS from commonNodeArgumentsFromEnv for local Nix builds if needed
              export K3S_CONTROL_PLANE_ADDR="${commonNodeArgumentsFromEnv.k3sControlPlaneAddr}"
            '';
          };
        }
      );
    }; # End outputs
}
