{
  description = "NixOS K3s Cluster on Hetzner Cloud with FluxCD";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, sops-nix, deploy-rs, nixos-anywhere, disko, ... }:
    let
      # Import the make-k3s-node function
      makeK3sNode = system: import ./k3s-cluster/lib/make-k3s-node.nix {
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      };
      
      # Common special arguments for all k3s nodes
      k3sCommonSpecialArgs = {
        k3sControlPlaneAddr = "10.0.0.2"; # IP of the control plane node
        k3sToken = ""; # Will be provided by sops-nix
        tailscaleAuthKey = ""; # Will be provided by sops-nix
      };
      
      # Systems supported
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      # NixOS configurations for the nodes
      nixosConfigurations = {
        # Hetzner control plane node
        "hetzner-control-01" = makeK3sNode "x86_64-linux" {
          hostname = "hetzner-control-01";
          role = "control";
          location = "hetzner";
          k3sControlPlaneAddr = k3sCommonSpecialArgs.k3sControlPlaneAddr;
          k3sToken = k3sCommonSpecialArgs.k3sToken;
          tailscaleAuthKey = k3sCommonSpecialArgs.tailscaleAuthKey;
          extraModules = [
            sops-nix.nixosModules.sops
            ./k3s-cluster/secrets.nix
            disko.nixosModules.disko
          ];
        };
        
        # Hetzner worker node
        "hetzner-worker-static-01" = makeK3sNode "x86_64-linux" {
          hostname = "hetzner-worker-static-01";
          role = "worker";
          location = "hetzner";
          k3sControlPlaneAddr = k3sCommonSpecialArgs.k3sControlPlaneAddr;
          k3sToken = k3sCommonSpecialArgs.k3sToken;
          tailscaleAuthKey = k3sCommonSpecialArgs.tailscaleAuthKey;
          extraModules = [
            sops-nix.nixosModules.sops
            ./k3s-cluster/secrets.nix
            disko.nixosModules.disko
          ];
        };
      };
      
      # Deploy-rs configuration
      deploy.nodes = {
        "hetzner-control-01" = {
          hostname = "hetzner-control-01";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hetzner-control-01;
            sshUser = "nixos";
            secrets = {
              "sops-key" = {
                local = "${builtins.getEnv "HOME"}/.config/sops/age/keys.txt";
                remote = "/var/lib/sops-nix/key.txt";
                permissions = "0400";
                user = "root";
                group = "root";
              };
            };
          };
        };
        
        "hetzner-worker-static-01" = {
          hostname = "hetzner-worker-static-01";
          profiles.system = {
            user = "root";
            path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hetzner-worker-static-01;
            sshUser = "nixos";
            secrets = {
              "sops-key" = {
                local = "${builtins.getEnv "HOME"}/.config/sops/age/keys.txt";
                remote = "/var/lib/sops-nix/key.txt";
                permissions = "0400";
                user = "root";
                group = "root";
              };
            };
          };
        };
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Basic tools
            git
            curl
            wget
            jq
            yq
            
            # Nix tools
            nixpkgs-fmt
            
            # Cloud tools
            hcloud
            kubectl
            kubernetes-helm
            fluxcd
            
            # Deployment tools
            deploy-rs.packages.${system}.deploy-rs
            sops
            age
            
            # NixOS Anywhere
            nixos-anywhere.packages.${system}.nixos-anywhere
            
            # Task automation
            just
            
            # GitHub CLI
            gh
            
            # Tailscale
            tailscale
          ];

          shellHook = ''
            # Non-sensitive environment variables
            
            # 1. User Preferences & Access
            export ADMIN_USERNAME="nixos"
            export ADMIN_PUBLIC_IP="136.38.60.5"
            export YOUR_DOMAIN="evan.institute"
            
            # 2. Hetzner Cloud Settings
            export HETZNER_LOCATION="ash"
            export HETZNER_NETWORK_ZONE="us-east"
            export PRIVATE_NETWORK_NAME="k3s-net"
            export FIREWALL_NAME="k3s-fw"
            export HETZNER_SSH_KEY_NAME="blade-nixos SSH Key"
            export CONTROL_PLANE_VM_TYPE="cpx31"
            export WORKER_VM_TYPE="cpx21"
            export PLACEMENT_GROUP_NAME="k3s-placement-group"
            export K3S_CLUSTER_NAME="k3s-us-east"
            export HETZNER_PRIVATE_IFACE="ens10" # Verification Required! Check the actual private interface name on a Hetzner VM
            
            # 4. Kubernetes & K3s Settings
            export K3S_CONTROL_PLANE_ADDR="10.0.0.2"
            export CLUSTER_IDENTIFIER="k8s-cluster=k3s-us-east"
            export CONTROL_PLANE_POOL="k8s-nodepool=control-plane"
            export STATIC_WORKER_POOL="k8s-nodepool=static-workers"
            export AUTOSCALED_WORKER_POOL="k8s-nodepool=general-autoscaled"
            export CLUSTER_AUTOSCALER_MIN_NODES="1"
            export CLUSTER_AUTOSCALER_MAX_NODES="5"
            export CLUSTER_AUTOSCALER_NODES="1:5:k8s-nodepool=general-autoscaled"
            
            # 5. NixOS Settings
            export NIXOS_STATE_VERSION="24.11"
            export HETZNER_KERNEL_MODULES="virtio_pci virtio_scsi nvme ata_piix uhci_hcd"
            
            # 6. Paths
            export HARDWARE_INFO_PATH="/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/hardware-info"
            export NIXOS_CONFIG_PATH="/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs"
            export FLUX_CONFIG_PATH="/home/evan/2_Dev/2.1_Homelab/!kube-flux"
            
            # 7. Attic Configuration
            export ATTIC_NAMESPACE="attic"
            
            # 8. GitHub Configuration
            export GITHUB_USER="evanlhatch"
            export FLUX_REPO="!kube-flux" # has not been made yet
            export TAILSCALE_DOMAIN="cinnamon-galaxy.ts.net"
            
            # Synology
            export MINIO_SYNOLOGY="hatchnas.cinnamon-galaxy.ts.net"
            export MINIO_ACCESS_KEY="minioadmin" # not created yet
            
            # SigNoz (Observability)
            export SIGNOZ_OTLP_ENDPOINT="http://signoz-backend.observability.svc.cluster.local:4317"
            
            echo "NixOS K3s Cluster on Hetzner Cloud development environment loaded"
            echo "Non-sensitive environment variables set from flake.nix devShell"
            echo "Sensitive environment variables loaded from .env via direnv"
          '';
        };
      }
    );
}
