# NixOS K3s Cluster on Hetzner Cloud with FluxCD - Final Implementation Plan

This augmented implementation plan builds on the original plan, incorporating specific details from your existing NixOS configuration at `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs`, your Flux setup at `/home/evan/2_Dev/2.1_Homelab/!kube-flux`, and the full suite of chosen open-source tools. It provides concrete code examples, integration points, and detailed steps for setting up the foundation of your cluster.

## Core Philosophy

1. **Declarative Nodes (NixOS Repo):** Your NixOS Flake at `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs` is the single source of truth, defining the complete OS state, k3s installation, networking, base packages (including Tailscale, Netdata), and security settings for all nodes using the generic builder pattern (`make-k3s-node` within `./k3s-cluster/lib/`) for consistency and maintainability.

2. **Declarative Cluster State (Flux Repo):** Your Flux repository at `/home/evan/2_Dev/2.1_Homelab/!kube-flux` defines all Kubernetes resources under the clusters/hetzner path via manifests (YAML, Kustomize, HelmReleases). FluxCD ensures the cluster state converges to the state defined in Git.

3. **Manual Component Integration:** Essential Kubernetes add-ons (Hetzner CCM/CSI, Traefik, Cert-Manager, Harbor, Infisical Operator, SigNoz Collectors, Grafana, Velero, Flagger, Falco, Kyverno, Pixie, etc.) are explicitly installed and configured via Flux definitions in the Flux repo.

4. **Layered Networking:** Hetzner Private Networks provide the primary, efficient substrate for inter-node k3s communication. Tailscale is layered across all nodes via NixOS for secure administrative access, simplified node discovery (using Tailscale DNS), and optional secure service exposure.

5. **Centralized Secrets:** Infisical serves as the primary store for application/service secrets, synced into Kubernetes via the Infisical Operator. sops-nix handles secrets required during the NixOS build or node bootstrap phase (e.g., K3s token, Tailscale auth key).

## Key Implementation Recommendations

Based on the review, the following key recommendations have been incorporated into this final plan:

### 1. Path Consistency
- **Root Directory:** All paths consistently use `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs` as the root for NixOS configurations.
- **Relative Paths:** All relative paths within Nix files (e.g., `../secrets/secrets.yaml` from modules/) are adjusted accordingly.
- **Script Paths:** All cd commands, file paths in scripts (`./env-vars.sh`, `./justfile`), and relative paths use the correct root directory.

### 2. Environment Variable Management with direnv
- **Nix-Managed Environment:** Use direnv with `.envrc` and `.env` files instead of `env-vars.sh` for a more Nix-native approach.
- **HETZNER_PRIVATE_IFACE:** Verify the actual name of the Hetzner private network interface on the VMs (e.g., ens10, eth1) and ensure this variable is correctly set. This is crucial for the `--flannel-iface` flag in `roles/k3s-control.nix`.
- **ADMIN_PUBLIC_IP:** Ensure this is correctly set for the firewall rules.
- **Non-Secret Variables:** Define in the flake's devShell shellHook.
- **Secret Variables:** Store in a gitignored `.env` file that is loaded by direnv.

### 3. Flake Implementation
- **specialArgs:** Pass node-specific parameters like the control plane IP (`k3sControlPlaneAddr`) via specialArgs when calling makeK3sNode in flake.nix outputs (nixosConfigurations).
- **Environment Variables:** While using builtins.getEnv within the role module works, specialArgs is generally cleaner Nix practice for node-specific config.

### 4. Sops-Nix Private Key Distribution
- **Key Distribution:** Implement a concrete plan for securely distributing the private age key (referenced by `sops.age.keyFile = "/var/lib/sops-nix/key.txt"` in secrets.nix) to each node.
- **Deploy-rs:** Use deploy-rs's secrets feature for secure key distribution.

### 5. Minor Refinements
- **Role Selector Logic:** Ensure consistent implementation in roles/*.nix (specifically `services.k3s.enable = ...`) and the selector script in nodes/hetzner-k3s-node/default.nix.
- **Justfile build-k3s-image:** Add the `--impure` flag to the nix build command if the flake relies on environment variables during evaluation.
- **Worker Node IP:** Remove the attempt to dynamically determine the worker IP within the Nix evaluation (nodeIpCmd in k3s-worker.nix) as it's fragile. Rely on k3s auto-detection or the `--flannel-iface` flag.

## Integration with Existing NixOS Configuration

- **NixOS Root:** All NixOS configurations reside within `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs`.
- **K3s Config Path:** Cluster-specific NixOS configurations are organized under `./k3s-cluster/`.
- **Flux Root:** Kubernetes configurations are managed within `/home/evan/2_Dev/2.1_Homelab/!kube-flux`.
- **Justfile:** Commands are added to `./justfile`.
- **Environment:** Variables managed through direnv with `.envrc` and `.env` files for a Nix-native approach.
- **Hardware:** Existing hardware information (facter data, hardware-configuration.nix files) is leveraged for node definitions.
## Phase 1: Prerequisites and Environment Setup

### 1.1: Set Up Environment with direnv

- [ ] Navigate to your NixOS config directory: `cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs`
- [ ] Create/update `.envrc` file:
  ```bash
  # /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/.envrc
  
  # Use the default devShell defined in flake.nix
  # This loads packages and runs the shellHook (setting non-secret vars)
  use flake .
  
  # Source secrets from a gitignored .env file in this directory
  # The file should contain 'export KEY=VALUE' lines for secrets
  # Make sure .env is in your .gitignore!
  source_env .env
  ```

- [ ] Create `.env` file for secrets (and add to `.gitignore`):
  ```bash
  # /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/.env
  # SECRETS ONLY - Add this file to .gitignore!
  # Use 'export' because we are using direnv's 'source_env'
  
  export AGE_PRIVATE_KEY="AGE-SECRET-KEY-..."
  export HETZNER_API_TOKEN="FrSvv..."
  export GITHUB_TOKEN="ghp_..." # Handle securely if repo public
  export TAILSCALE_AUTH_KEY="tskey-auth-..." # Needed for sops encrypt step
  export MINIO_SECRET_KEY="minioadmin-secret"
  export INFISICAL_SERVICE_TOKEN="st.xyz..." # Token for Infisical Operator bootstrap secret
  export ATTIC_TOKEN_SIGNING_SECRET="a-very-strong-random-secret-for-attic-tokens" # For Infisical->Attic secret sync
  # Add the generated K3S_TOKEN here after generating it once
  export K3S_TOKEN="generated-k3s-token-value"
  # Add any other truly sensitive values needed in the environment
  # export SIGNOZ_INGESTION_KEY="xyz..." # Example
  ```

- [ ] Activate direnv: `direnv allow .`
- [ ] Verify essential variables are loaded:
  ```bash
  env | grep -E 'ADMIN_USERNAME|ADMIN_SSH_PUBLIC_KEY|ADMIN_PUBLIC_IP|AGE_PRIVATE_KEY|HETZNER_API_TOKEN|HETZNER_SSH_KEY_NAME|HETZNER_LOCATION|HETZNER_PRIVATE_IFACE|PRIVATE_NETWORK_NAME|FIREWALL_NAME|CONTROL_PLANE_VM_TYPE|WORKER_VM_TYPE|K3S_TOKEN|TAILSCALE_AUTH_KEY|NIXOS_STATE_VERSION|GITHUB_TOKEN|FLUX_REPO'
  ```

**Test**: Confirm all required variables display values.

**Context**: This direnv-based approach provides a more Nix-native way to manage environment variables. Non-sensitive configuration is managed through the flake's devShell shellHook, while secrets are stored in a gitignored `.env` file. This keeps your flake.nix focused on the buildable artifacts and the declarative part of the dev environment, while segregating secrets cleanly.

**Implementation Detail**: Ensure the K3S_TOKEN is securely generated and present. Run this once if the token is missing or needs refreshing:

```bash
# Run from /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs directory
if [ -z "$K3S_TOKEN" ] || [ "$K3S_TOKEN" == "" ]; then # Check if empty or literally ""
  echo "Generating new K3S_TOKEN..."
  NEW_K3S_TOKEN=$(openssl rand -hex 32)
  if [ $(echo -n "$NEW_K3S_TOKEN" | wc -c) -eq 64 ]; then
     echo "Updating .env with new K3S_TOKEN..."
     # Use perl for robust in-place editing
     perl -i -pe "s/^export K3S_TOKEN=.*/export K3S_TOKEN=\"$NEW_K3S_TOKEN\"/" .env
     # Re-allow direnv to reload the environment
     direnv allow .
     echo "K3S_TOKEN updated and loaded via direnv."
   else
     echo "Error generating K3S_TOKEN." >&2
     exit 1
   fi
else
    echo "K3S_TOKEN already set."
fi
```

### 1.2: Verify Hetzner Account Access

- [ ] Log in to Hetzner Cloud Console. Verify project access.
- [ ] Test API token permissions: `hcloud server list` (ensure $HETZNER_API_TOKEN is exported via direnv).
**Test**: Command executes successfully, showing 0 servers initially or existing ones.

**Context**: Requires a functional Hetzner Cloud account and an API token with Read/Write permissions assigned to $HETZNER_API_TOKEN in your .env file.

### 1.3: Generate K3s Token

(This step is now integrated into step 1.1)

### 1.4: Verify Required Tools

- [ ] Check versions:
  ```bash
  nix --version
  sops --version
  age --version
  hcloud version
  kubectl version --client
  helm version
  flux --version
  deploy --version
  just --version
  gh --version  # if using GitHub releases
  ```

**Test**: Each command returns a version string without errors.

**Context**: These CLIs are fundamental for the entire workflow, from building NixOS to managing K8s and interacting with Hetzner/GitHub.

**Implementation Detail**: Install any missing tools using your preferred Nix method (e.g., add to environment.systemPackages in your host's NixOS config, use nix profile install, or use nix-shell -p <tool>):

```bash
# Example using nix profile (per-user)
# nix profile install nixpkgs#sops nixpkgs#age nixpkgs#hcloud nixpkgs#kubectl \
#   nixpkgs#kubernetes-helm nixpkgs#fluxcd nixpkgs#deploy-rs nixpkgs#just nixpkgs#gh
```

## Phase 2: Repository Structure Setup

### 2.1: Set Up NixOS Repository Structure

**Context**: This establishes the modular layout within your existing NixOS configuration (/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs) specifically for the K3s cluster components. This promotes organization and reusability via the builder pattern.

**Implementation Detail**: Create directories:

```bash
# Run from /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs directory
mkdir -p ./k3s-cluster/{lib,modules,profiles,roles,locations,hardware-configs,nodes/hetzner-k3s-node,installer,secrets}
```

**Visual File Tree**:
```
/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/
├── flake.nix
├── flake.lock
├── justfile
├── .envrc
├── .env  # gitignored
├── k3s-cluster/
│   ├── common.nix
│   ├── lib/
│   │   └── make-k3s-node.nix
│   ├── modules/
│   │   ├── tailscale.nix
│   │   ├── netdata.nix
│   │   └── disko-*.nix (Optional)
│   ├── profiles/
│   │   └── base-server.nix
│   ├── roles/
│   │   ├── k3s-control.nix
│   │   └── k3s-worker.nix
│   ├── locations/
│   │   ├── hetzner.nix
│   │   ├── hetzner-hardware.nix
│   │   └── local.nix
│   ├── hardware-configs/
│   │   ├── local-worker-1.nix
│   │   └── ...
│   ├── nodes/
│   │   └── hetzner-k3s-node/
│   │       └── default.nix (Image builder config)
│   ├── installer/
│   │   └── default.nix (Installer ISO config)
│   ├── secrets/
│   │   └── secrets.yaml (Encrypted secrets)
│   ├── .sops.yaml (Sops config for this dir)
│   └── README.md
├── secrets.yaml (Main sops config for repo?)
└── ... (Your other existing NixOS config files/dirs)
Test: tree ./k3s-cluster -d shows the expected directories.
[ ] 2.2: Prepare Existing Flux Repository Structure

Context: Sets up the target directory within your established Flux repository (!kube-flux) where all Kubernetes manifests for this specific Hetzner cluster will reside, managed by Flux.
Implementation Detail: Ensure you are on the correct branch (hetzner-cluster or similar) and create the necessary subdirectories:
Bash

cd /home/evan/2_Dev/2.1_Homelab/\!kube-flux
git checkout hetzner-cluster # Or git switch hetzner-cluster
mkdir -p clusters/hetzner/{core,infrastructure,apps,observability,security,delivery,registry,secrets-sync,backup}
# Add .gitkeep files to empty dirs if desired
git add clusters/hetzner
git commit -m "feat(hetzner): Set up cluster directory structure"
# git push origin hetzner-cluster
Test: tree /home/evan/2_Dev/2.1_Homelab/\!kube-flux/clusters/hetzner -d shows the structure.
[ ] 2.3: Create Initial README Files

Context: Basic documentation explaining the purpose of the new directories.
Implementation Detail:
Create ./k3s-cluster/README.md:
Markdown

# NixOS K3s Cluster on Hetzner Cloud

This directory contains the NixOS configuration specific to the K3s Kubernetes cluster running on Hetzner Cloud, managed within the parent NixOS flake at `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs`. It uses a generic builder pattern (`lib/make-k3s-node`) for consistency.

## Directory Structure

- `lib/`: Generic node builder function (`make-k3s-node.nix`).
- `modules/`: Reusable NixOS service modules (Tailscale, Netdata, Disko).
- `profiles/`: Common node profiles (`base-server.nix`).
- `roles/`: k3s role specifics (`k3s-control.nix`, `k3s-worker.nix`).
- `locations/`: Environment specifics (`hetzner.nix`, `local.nix`).
- `hardware-configs/`: Machine-specific hardware files (for local nodes).
- `nodes/`: Configurations used for building specific artifacts (e.g., Hetzner image).
- `installer/`: Configuration for the local USB installer ISO.
- `secrets/`: Encrypted secrets definition (`secrets.yaml`) managed by sops-nix.
- `.sops.yaml`: SOPS configuration for this directory.

## Usage

See the main `./justfile` for common build, deployment, and management commands related to this cluster. Node definitions and build outputs are configured in `./flake.nix`.
Create /home/evan/2_Dev/2.1_Homelab/!kube-flux/clusters/hetzner/README.md:
Markdown

# Hetzner k3s Cluster Configuration (Flux Managed)

This directory contains all Kubernetes manifests defining the desired state for the k3s cluster running on Hetzner Cloud. FluxCD monitors this path in the Git repository.

## Directory Structure

- `core/`: Base namespaces, essential CRDs (if not installed by Helm charts).
- `infrastructure/`: Core cluster services (Hetzner CCM, CSI, SUC, CA).
- `secrets-sync/`: Secrets synchronization (Infisical Operator, InfisicalSecret CRs).
- `registry/`: Container Registry (Harbor).
- `apps/`: Core applications & ingress (Traefik, Cert-Manager, ClusterIssuers, Middleware).
- `observability/`: Monitoring, Logging, Tracing (SigNoz Collectors, Grafana, Pixie).
- `security/`: Security tooling (Falco, Kyverno policies).
- `delivery/`: Progressive Delivery (Flagger).
- `backup/`: Backup tooling (Velero, BackupStorageLocation, Schedules).
Test: Files exist and contain descriptive content.
[ ] 2.4: Update Justfile for Common Commands

Context: Adds convenient aliases to ./justfile for common operations related to this cluster setup. Ensure firewall rules in create-hetzner-firewall include necessary ports for all planned tools (Traefik 80/443, Etcd 2379/2380 for future HA).
Implementation Detail: Add/merge the justfile recipes provided in your plan into your existing ./justfile. Ensure variables like ${HETZNER_LOCATION:-ash} and labels applied during node creation are correct. Self-correction: Add firewall rules for Traefik.
Code snippet

# K3s Cluster Commands (Add or merge into existing ./justfile)

# ... (build-k3s-image, compress-k3s-image, register-k3s-image from your plan) ...

create-hetzner-network:
    hcloud network create --name ${PRIVATE_NETWORK_NAME:-k3s-net} --ip-range 10.0.0.0/16
    # Add subnet specific to your location
    hcloud network add-subnet ${PRIVATE_NETWORK_NAME:-k3s-net} --network-zone ${HETZNER_NETWORK_ZONE:-us-east} --type server --ip-range 10.0.0.0/24

create-hetzner-firewall:
    hcloud firewall create --name ${FIREWALL_NAME:-k3s-fw}
    # Base Rules
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 22 --source-ips ${ADMIN_PUBLIC_IP}/32 --description "SSH from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips ${ADMIN_PUBLIC_IP}/32 --description "ICMP from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips 10.0.0.0/16 --description "ICMP from Private Net"
    # K3s Core Rules
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 6443 --source-ips 10.0.0.0/16,${ADMIN_PUBLIC_IP}/32 --description "K3s API"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 10250 --source-ips 10.0.0.0/16 --description "Kubelet"
    # K3s HA Etcd Rules (Add now for future readiness)
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 2379 --source-ips 10.0.0.0/16 --description "Etcd Client"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 2380 --source-ips 10.0.0.0/16 --description "Etcd Peer"
    # CNI Rules (Flannel Default - Adjust for Cilium later)
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol udp --port 51820 --source-ips 10.0.0.0/16 --description "Flannel WireGuard"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol udp --port 8472 --source-ips 10.0.0.0/16 --description "Flannel VXLAN (Fallback)"
    # Ingress Rules (Allow from ANY initially, restrict later if needed)
    # Or restrict to Tailscale IPs if using Tailscale Funnel primarily
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0 --description "Traefik HTTP"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0 --description "Traefik HTTPS"

create-hetzner-placement-group:
     hcloud placement-group create --name ${PLACEMENT_GROUP_NAME:-k3s-placement-group} --type spread

create-control-node: # Uses HETZNER_IMAGE_NAME, CONTROL_PLANE_VM_TYPE, etc from env
     hcloud server create \
       --name hetzner-control-01 \
       --image ${HETZNER_IMAGE_NAME} \
       --type ${CONTROL_PLANE_VM_TYPE} \
       --location ${HETZNER_LOCATION} \
       --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
       --firewall ${FIREWALL_NAME:-k3s-fw} \
       --ssh-key ${HETZNER_SSH_KEY_NAME} \
       --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
       --label k8s-cluster=${K3S_CLUSTER_NAME:-k3s-us-east} \
       --label k8s-nodepool=control-plane \
       --user-data '#cloud-config\nwrite_files:\n- path: /etc/nixos/k3s_role\n  content: control\n'

create-worker-node number="1" pool="static-workers" type="{{ WORKER_VM_TYPE:-cpx21 }}": # Allow pool label + type override
     hcloud server create \
       --name hetzner-worker-{{pool}}-{{number}} \
       --image ${HETZNER_IMAGE_NAME} \
       --type {{type}} \
       --location ${HETZNER_LOCATION} \
       --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
       --firewall ${FIREWALL_NAME:-k3s-fw} \
       --ssh-key ${HETZNER_SSH_KEY_NAME} \
       --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
       --label k8s-cluster=${K3S_CLUSTER_NAME:-k3s-us-east} \
       --label k8s-nodepool={{pool}} \
       --user-data '#cloud-config\nwrite_files:\n- path: /etc/nixos/k3s_role\n  content: worker\n'

# ... (get-kubeconfig, bootstrap-flux, update-traefik-tailscale, create-tailscale-route from your plan) ...

# Add deploy-rs targets (assuming deploy-rs config in flake.nix)
deploy-control-node:
    deploy .#hetzner-control-01

deploy-worker-node number="1" pool="static-workers":
    deploy .#hetzner-worker-{{pool}}-{{number}} # Ensure flake matches this naming

# Build installer ISO
build-installer-iso:
     nix build .#installerIso --out-link k3s-installer.iso

# Example sops edit command
sops-edit:
     sops ./k3s-cluster/secrets/secrets.yaml
Test: just --list shows the new commands.
Phase 3: NixOS Configuration Files
(All file paths relative to ./k3s-cluster/ unless specified)

[ ] 3.1: Common Configuration (common.nix)

Context: Defines base user (${ADMIN_USERNAME:-nixos}), SSH key (${ADMIN_SSH_PUBLIC_KEY}), timezone, locale, common packages.
Implementation:
Nix

# ./k3s-cluster/common.nix
# (Code from your Plan - Phase 3.1)
{ config, lib, pkgs, specialArgs, ... }:
{
  time.timeZone = "Etc/UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.${builtins.getEnv "ADMIN_USERNAME" or "nixos"} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ]; # Add docker group if needed
    openssh.authorizedKeys.keys = [
      (builtins.getEnv "ADMIN_SSH_PUBLIC_KEY" or "ssh-rsa ...") # Use env var or default
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = { PasswordAuthentication = false; PermitRootLogin = "prohibit-password"; };
  };

  environment.systemPackages = with pkgs; [ git curl wget htop vim tmux jq ];
  nixpkgs.config.allowUnfree = true;
}
Test: nix-instantiate --parse ./k3s-cluster/common.nix.
[ ] 3.2: Node Builder Function (lib/make-k3s-node.nix)

Context: Central factory for creating NixOS node configurations. Imports base profile, role, location, hardware configs.
Implementation:
Nix

# ./k3s-cluster/lib/make-k3s-node.nix
# (Code from your Plan - Phase 3.2)
{ lib, pkgs }:
{ hostname ? "nixos",
  system ? "x86_
You stopped this response





stop and try it again. remember that this is not in ~/nixos but in /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs



the project directory is /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs you can state that once and then use relative paths to save token space




Show thinking
Okay, restarting the generation of the final comprehensive guide, using /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs as the base directory for the NixOS configuration and incorporating all discussed details and code examples into the user-provided plan structure.

This is Part 1 (Phases 1-4).

Definitive Guide: Building & Operating a Modern NixOS-based k3s Homelab on Hetzner Cloud (2025)

(Based on NixOS configuration at: /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs)

1. Introduction

This guide provides a comprehensive walkthrough for establishing and managing a resilient, scalable, and feature-rich Kubernetes (k3s) cluster hosted on Hetzner Cloud. It leverages your specific NixOS flake configuration located at /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs (hereafter referred to as the "NixOS Config Repo") for declarative infrastructure-as-code (IaC) node management and your existing FluxCD setup at /home/evan/2_Dev/2.1_Homelab/!kube-flux (hereafter referred to as the "Flux Repo") for GitOps-based cluster state configuration. This setup is tailored for a sophisticated personal or small-group homelab environment, emphasizing best-in-class open-source tooling relevant in 2025.

Core Chosen Technologies:

Orchestration: k3s
Node OS / IaC: NixOS (via Flake, Generic Builder Pattern)
Cloud Provider: Hetzner Cloud
Cluster GitOps: FluxCD
Ingress: Traefik Proxy
Certificates: Cert-Manager (with Let's Encrypt)
Registry: Harbor
Secrets: Infisical (via K8s Operator) + sops-nix (for bootstrap)
Observability: SigNoz (Backend), Grafana (UI), Netdata (Node), OpenTelemetry Collector (Shipping), Pixie (eBPF)
Backup: Velero (with MinIO on Synology NAS)
Progressive Delivery: Flagger
Security: Falco (Runtime), Kyverno (Policy)
Networking: Flannel (initially) -> Cilium (planned), Tailscale (Overlay/Access)
CI/CD: GitHub Actions
Stateful Apps: Kubernetes Operators (as needed)
Deployment Tooling: deploy-rs
2. Core Philosophy & Architecture

Declarative Nodes (NixOS Repo): Your NixOS flake repository is the single source of truth for node configurations. The make-k3s-node builder ensures consistency. Node updates are managed declaratively via deploy-rs or image rebuilds.
Declarative Cluster State (Flux Repo): Your Flux repository defines all Kubernetes resources deployed within the cluster. FluxCD ensures the cluster state matches the Git state defined under the clusters/hetzner path.
Single Hetzner Image: A generic NixOS image artifact is built from the NixOS Config Repo, capable of booting as either a control-plane or worker node, with the role determined at provision time via cloud-init user-data.
Explicit Component Integration: All add-ons (Hetzner CCM/CSI, Traefik, Harbor, Infisical Operator, SigNoz Collectors, Grafana, Velero, Flagger, Falco, Kyverno, Pixie, etc.) are deployed and configured explicitly via Flux definitions (HelmRelease, Kustomization) in the Flux Repo.
Layered Networking: Hetzner Private Networks provide the primary, efficient substrate for inter-node k3s communication. Tailscale provides a secure overlay network for admin access and simplified node discovery (using Tailscale DNS).
Centralized Secrets: Infisical serves as the primary store for application/service secrets, synced into Kubernetes via its Operator. sops-nix handles secrets required during the NixOS build or node bootstrap phase (k3s token, Tailscale auth key).
3. Integration with Existing Configuration

NixOS Root: /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs
K3s Config Path: Cluster-specific NixOS configurations are organized under ./k3s-cluster/ within the NixOS Config Repo root.
Flux Root: /home/evan/2_Dev/2.1_Homelab/!kube-flux
Justfile: Commands are added to ./justfile within the NixOS Config Repo root.
Environment: Variables managed through direnv with `.envrc` and `.env` files within the NixOS Config Repo root.
Hardware: Existing hardware information (facter data, .nix files) from previous setups is leveraged for node definitions within the NixOS Config Repo.
Phase 1: Prerequisites and Environment Setup
[ ] 1.1: Verify Environment Variables

**Context**: Centralized configuration via direnv with `.envrc` and `.env` files provides a Nix-native approach to environment management. Non-sensitive configuration is managed through the flake's devShell shellHook, while secrets are stored in a gitignored `.env` file. This keeps your flake.nix focused on the buildable artifacts and the declarative part of the dev environment, while segregating secrets cleanly.

**Implementation Detail**:
Bash

cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs # Navigate to NixOS repo root
# direnv will automatically load the environment
# Verify key variables exist (adjust grep pattern for all needed vars)
env | grep -E 'ADMIN_USERNAME|ADMIN_SSH_PUBLIC_KEY|ADMIN_AGE_PUBLIC_KEY|AGE_PRIVATE_KEY|HETZNER_TOKEN|HETZNER_SSH_KEY_NAME|HETZNER_LOCATION|PRIVATE_NETWORK_NAME|FIREWALL_NAME|CONTROL_PLANE_VM_TYPE|WORKER_VM_TYPE|K3S_TOKEN|TAILSCALE_AUTH_KEY|NIXOS_STATE_VERSION|GITHUB_USER|GITHUB_TOKEN|FLUX_REPO'
# Ensure K3S_TOKEN is generated and set (run once if needed)
if [ -z "$K3S_TOKEN" ] || [ "$K3S_TOKEN" == "" ]; then
  echo "Generating new K3S_TOKEN..."
  NEW_K3S_TOKEN=$(openssl rand -hex 32)
  if [ $(echo -n "$NEW_K3S_TOKEN" | wc -c) -eq 64 ]; then
     echo "Updating env-vars.sh with new K3S_TOKEN..."
     perl -i -pe "s/^export K3S_TOKEN=.*/export K3S_TOKEN=\"$NEW_K3S_TOKEN\"/" ./env-vars.sh
     source ./env-vars.sh # Re-source
     echo "K3S_TOKEN updated and sourced."
   else
     echo "Error generating K3S_TOKEN." >&2; exit 1;
   fi
else
    echo "K3S_TOKEN already set."
fi
Test: Confirm all required variables are available in the environment.
[ ] 1.2: Verify Hetzner Account Access

Context: Requires a functional Hetzner Cloud account and an API token ($HETZNER_TOKEN) with Read/Write permissions.
Implementation Detail:
Bash

# HETZNER_API_TOKEN is automatically exported by direnv
hcloud server list
Test: Command succeeds and lists 0 or more servers.
[ ] 1.3: Generate K3s Token

(This step is integrated into step 1.1)
Context: This secure shared secret allows K3s agents to join the control plane. It will be encrypted via sops-nix.
[ ] 1.4: Verify Required Tools

Context: Essential CLI tools for building, managing secrets, interacting with cloud/K8s, and deploying.
Implementation Detail: Check versions:
Bash

nix --version
sops --version
age --version
hcloud version
kubectl version --client
helm version
flux --version
deploy --version # deploy-rs
just --version
gh --version # If using GitHub Releases for image hosting
Install missing tools via your preferred Nix method (system packages, nix profile install, or nix-shell -p ...).
Test: Each command returns a version string without errors.
Phase 2: Repository Structure Setup
[ ] 2.1: Set Up NixOS Repository Structure

Context: Establishes the modular layout within /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs for K3s components, supporting the builder pattern.
Implementation Detail:
Bash

cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
mkdir -p ./k3s-cluster/{lib,modules,profiles,roles,locations,hardware-configs,nodes/hetzner-k3s-node,installer,secrets}
Visual File Tree:
!k3s-nixos-configs/
├── flake.nix
├── flake.lock
├── justfile
├── .envrc
├── .env  # gitignored
├── k3s-cluster/
│   ├── common.nix
│   ├── lib/make-k3s-node.nix
│   ├── modules/{tailscale.nix, netdata.nix, disko-*.nix}
│   ├── profiles/base-server.nix
│   ├── roles/{k3s-control.nix, k3s-worker.nix}
│   ├── locations/{hetzner.nix, hetzner-hardware.nix, local.nix}
│   ├── hardware-configs/{local-*.nix}
│   ├── nodes/hetzner-k3s-node/default.nix
│   ├── installer/default.nix
│   ├── secrets/secrets.yaml
│   ├── .sops.yaml
│   └── README.md
├── secrets.yaml # Optional: Main sops config for entire repo
└── ... # Your other existing NixOS config files/dirs
Test: tree ./k3s-cluster -d (from repo root) shows the expected directories.
[ ] 2.2: Prepare Existing Flux Repository Structure

Context: Organizes Kubernetes manifests for this specific Hetzner cluster within your established Flux repository (!kube-flux).
Implementation Detail:
Bash

cd /home/evan/2_Dev/2.1_Homelab/\!kube-flux
git checkout hetzner-cluster # Or your target branch
# Define all needed subdirs for the chosen tools
mkdir -p clusters/hetzner/{core,infrastructure,apps,observability,security,delivery,registry,secrets-sync,backup}
# Add .gitkeep to empty dirs if needed, commit and push
git add clusters/hetzner
git commit -m "feat(hetzner): Set up detailed cluster directory structure"
# git push origin hetzner-cluster
Test: tree /home/evan/2_Dev/2.1_Homelab/\!kube-flux/clusters/hetzner -d.
[ ] 2.3: Create Initial README Files

Context: Essential documentation for clarity and future reference.
Implementation Detail: Create ./k3s-cluster/README.md and !kube-flux/clusters/hetzner/README.md with descriptive content outlining the structure and purpose, as shown in the previous detailed response.
Test: Files exist and contain useful information.
[ ] 2.4: Update Justfile for Common Commands

Context: Provides convenient aliases in ./justfile (NixOS repo root) for setup and management tasks, using environment variables for configuration. Ensure firewall rules are comprehensive for all planned services.
Implementation Detail: Add/merge the Justfile recipes from your plan (Phase 2.4) into ./justfile. Ensure commands reference correct relative paths if needed. Verify firewall rules in create-hetzner-firewall include necessary ports (SSH 22, K8s API 6443, Kubelet 10250, Etcd 2379/2380, Flannel 51820/8472 UDP, Traefik 80/443 TCP, Netdata 19999 TCP, potentially others for specific add-ons). Make sure node creation commands apply correct labels (e.g., k8s-nodepool=control-plane, k8s-nodepool=static-workers, k8s-nodepool=autoscaled-workers).
Code snippet

# (Add to /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/justfile)
# K3s Cluster Commands

# Build the Hetzner K3s node image
build-k3s-image:
    nix build .#hetznerK3sNodeImage --impure # May need --impure if reading env vars

# Compress the Hetzner K3s node image
compress-k3s-image:
    zstd result/disk.raw -o hetzner-k3s-image.zst

# Register the Hetzner K3s node image
register-k3s-image url:
    hcloud image create --name ${HETZNER_IMAGE_NAME:-my-k3s-image-v1} --type snapshot --url {{url}}

# Create the Hetzner network
create-hetzner-network:
    hcloud network create --name ${PRIVATE_NETWORK_NAME:-k3s-net} --ip-range 10.0.0.0/16
    hcloud network add-subnet ${PRIVATE_NETWORK_NAME:-k3s-net} --network-zone ${HETZNER_NETWORK_ZONE:-us-east} --type server --ip-range 10.0.0.0/24

# Create the Hetzner firewall
create-hetzner-firewall:
    hcloud firewall create --name ${FIREWALL_NAME:-k3s-fw}
    # Base & Admin Access
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 22 --source-ips ${ADMIN_PUBLIC_IP}/32 --description "SSH from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips ${ADMIN_PUBLIC_IP}/32 --description "ICMP from Admin"
    # Private Network Access
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips 10.0.0.0/16 --description "ICMP from Private Net"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 6443 --source-ips 10.0.0.0/16,${ADMIN_PUBLIC_IP}/32 --description "K3s API"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 10250 --source-ips 10.0.0.0/16 --description "Kubelet"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 2379 --source-ips 10.0.0.0/16 --description "Etcd Client (for HA)"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 2380 --source-ips 10.0.0.0/16 --description "Etcd Peer (for HA)"
    # CNI (Flannel default)
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol udp --port 51820 --source-ips 10.0.0.0/16 --description "Flannel WireGuard"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol udp --port 8472 --source-ips 10.0.0.0/16 --description "Flannel VXLAN"
    # Ingress (Traefik) - Allow from anywhere initially, refine later if needed
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0 --description "Traefik HTTP"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0 --description "Traefik HTTPS"
    # Monitoring (Netdata Example)
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 19999 --source-ips 10.0.0.0/16,${ADMIN_PUBLIC_IP}/32 --description "Netdata" # Or Tailscale IPs

# Create the Hetzner placement group
create-hetzner-placement-group:
    hcloud placement-group create --name ${PLACEMENT_GROUP_NAME:-k3s-placement-group} --type spread

# Create the Hetzner control plane node
create-control-node:
    hcloud server create \
      --name hetzner-control-01 \
      --image ${HETZNER_IMAGE_NAME} \
      --type ${CONTROL_PLANE_VM_TYPE} \
      --location ${HETZNER_LOCATION} \
      --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
      --firewall ${FIREWALL_NAME:-k3s-fw} \
      --ssh-key ${HETZNER_SSH_KEY_NAME} \
      --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
      --label k8s-cluster=${K3S_CLUSTER_NAME:-k3s-us-east} \
      --label k8s-nodepool=control-plane \
      --user-data '#cloud-config\nwrite_files:\n- path: /etc/nixos/k3s_role\n  content: control\n'

# Create a Hetzner worker node
create-worker-node number="1" pool="static-workers" type="{{ WORKER_VM_TYPE:-cpx21 }}":
    hcloud server create \
      --name hetzner-worker-{{pool}}-{{number}} \
      --image ${HETZNER_IMAGE_NAME} \
      --type {{type}} \
      --location ${HETZNER_LOCATION} \
      --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
      --firewall ${FIREWALL_NAME:-k3s-fw} \
      --ssh-key ${HETZNER_SSH_KEY_NAME} \
      --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
      --label k8s-cluster=${K3S_CLUSTER_NAME:-k3s-us-east} \
      --label k8s-nodepool={{pool}} \
      --user-data '#cloud-config\nwrite_files:\n- path: /etc/nixos/k3s_role\n  content: worker\n'

# Get the kubeconfig from the control plane node
get-kubeconfig:
    #!/usr/bin/env bash
    CONTROL_IP=$(hcloud server ip hetzner-control-01)
    ssh ${ADMIN_USERNAME:-nixos}@$CONTROL_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | \
      sed "s/127.0.0.1/$CONTROL_IP/g" > ~/.kube/config.k3s # Save locally
    chmod 600 ~/.kube/config.k3s
    echo "Kubeconfig saved to ~/.kube/config.k3s"
    echo "Use it with: export KUBECONFIG=~/.kube/config.k3s"

# Bootstrap Flux
bootstrap-flux:
    #!/usr/bin/env bash
    # Ensure GITHUB_USER, GITHUB_TOKEN, FLUX_REPO are exported via direnv
    if [[ -z "$GITHUB_USER" || -z "$GITHUB_TOKEN" || -z "$FLUX_REPO" ]]; then
      echo "Error: GITHUB_USER, GITHUB_TOKEN, or FLUX_REPO environment variables missing." >&2; exit 1;
    fi
    flux bootstrap github \
      --owner=$GITHUB_USER \
      --repository=$FLUX_REPO \
      --branch=main \
      --path=clusters/hetzner \
      --personal # Use personal token

# ... (update-traefik-tailscale, create-tailscale-route from your plan) ...

# Deploy-rs commands
deploy-control:
    deploy .#hetzner-control-01
deploy-worker node="hetzner-worker-static-1":
    deploy .#{{node}}

# Build installer
build-installer:
    nix build .#installerIso --out-link k3s-installer.iso

# Sops edit helper
sops-edit:
     sops ./k3s-cluster/secrets/secrets.yaml
Test: cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs && just --list shows commands.
Phase 3: NixOS Configuration Files
(All file paths relative to /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/k3s-cluster/ unless otherwise noted)

[ ] 3.1: Create Common Configuration (common.nix)

Context: Base NixOS settings applied to all cluster nodes.
Implementation Detail:
Nix

# ./k3s-cluster/common.nix
# (Code from your Plan - Phase 3.1)
{ config, lib, pkgs, specialArgs, ... }: {
  time.timeZone = "Etc/UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.${builtins.getEnv "ADMIN_USERNAME" or "nixos"} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ]; # Add groups as needed
    openssh.authorizedKeys.keys = [
      (builtins.getEnv "ADMIN_SSH_PUBLIC_KEY") # Ensure this is set in flake's devShell shellHook
    ];
  };
  # Passwordless sudo for wheel group (use with caution)
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = { PasswordAuthentication = false; PermitRootLogin = "prohibit-password"; };
  };

  environment.systemPackages = with pkgs; [ git curl wget htop vim tmux jq ];
  nixpkgs.config.allowUnfree = true;

  # Basic network settings (can be refined in location/node configs)
  networking.hostName = config.networking.hostName or "nixos"; # Default if not set elsewhere
  networking.useDHCP = lib.mkDefault true; # Default, may be overridden
}
Test: nix-instantiate --parse ./k3s-cluster/common.nix.
[ ] 3.2: Create Node Builder Function (lib/make-k3s-node.nix)

Context: The core reusable function for defining NixOS node configurations based on role, location, and hardware.
Implementation Detail:
Nix

# ./k3s-cluster/lib/make-k3s-node.nix
# (Code from your Plan - Phase 3.2)
{ lib, pkgs }:
{ hostname ? "nixos",
  system ? "x86_64-linux",
  role, hardwareConfigPath, location,
  specialArgs ? {}, extraModules ? [], ... }:
lib.nixosSystem {
  inherit system specialArgs;
  modules = [
    # Base profile applied first
    ../profiles/base-server.nix
    # Location-specific settings (Hetzner vs Local)
    (lib.findFirst (p: p != null) null [
      (if location == "hetzner" then ../locations/hetzner.nix else null)
      (if location == "local" then ../locations/local.nix else null)
    ])
    # Role-specific settings (k3s control vs worker)
    (lib.findFirst (p: p != null) null [
      (if role == "control" then ../roles/k3s-control.nix else null)
      (if role == "worker" then ../roles/k3s-worker.nix else null)
    ])
    # Specific hardware configuration (required)
    hardwareConfigPath
    # Set hostname explicitly
    ({ config, ... }: { networking.hostName = hostname; })
    # Include any extra specific modules
  ] ++ extraModules;
}
Test: nix-instantiate --parse ./k3s-cluster/lib/make-k3s-node.nix.
[ ] 3.3: Create Service Modules (modules/)

Context: Reusable configurations for common services like Tailscale and Netdata.
Implementation Detail:
tailscale.nix:
Nix

# ./k3s-cluster/modules/tailscale.nix
# (Code from your Plan - Phase 3.3)
{ config, lib, pkgs, ... }: {
  services.tailscale = {
    enable = true;
    package = pkgs.tailscale;
    # Use sops-nix to provide the auth key securely
    authKeyFile = config.sops.secrets.tailscale_authkey.path;
    # Allow node to act as subnet router or exit node if needed later
    useRoutingFeatures = "both";
  };
  # Allow Tailscale traffic through NixOS firewall
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 41641 ];
  };
  # Define the sops secret structure needed by this module
  sops.secrets.tailscale_authkey = {
    # Assumes secrets.yaml is one level up from ./modules directory
    sopsFile = ../secrets/secrets.yaml;
    owner = config.users.users.tailscaled.user; # Run as tailscaled user
    group = config.users.users.tailscaled.group;
    mode = "0400";
  };
}
netdata.nix:
Nix

# ./k3s-cluster/modules/netdata.nix
# (Code from your Plan - Phase 3.3)
{ config, lib, pkgs, ... }: {
  services.netdata = {
    enable = true;
    # Keep config minimal, can be expanded later
    config = { global = { "memory mode" = "dbengine"; "page cache size" = 32; }; };
    # Add python packages if netdata plugins need them
    # python.extraPackages = ps: [ ps.requests ];
  };
  # Allow access to Netdata dashboard via firewall (restrict source IPs if needed)
  networking.firewall.allowedTCPPorts = [ 19999 ];
}
(Optional) disko-control.nix / disko-worker.nix: Include Disko configurations here if using declarative partitioning. (Code from your Plan - Phase 3.9).
Test: Parse individual module files.
[ ] 3.4: Create Base Server Profile (profiles/base-server.nix)

Context: Consolidates common configuration applied to ALL cluster nodes by importing base settings and service modules. Includes k3s package and openiscsi needed for CSI.
Implementation Detail:
Nix

# ./k3s-cluster/profiles/base-server.nix
# (Code from your Plan - Phase 3.4)
{ config, pkgs, inputs, lib, specialArgs, ... }: {
  imports = [
    ../common.nix
    ../modules/tailscale.nix
    ../modules/netdata.nix
    # Import the main sops-nix module to enable secret management
    inputs.sops-nix.nixosModules.sops
  ];

  # Bootloader (can be overridden by location/hardware)
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Base Networking (can be overridden)
  networking.firewall.enable = true;

  # Base Services
  services.timesyncd.enable = true;
  # Required for Hetzner Block Storage / CSI driver PVs
  services.openiscsi.enable = true;

  # System State Version (Important for NixOS stability)
  system.stateVersion = builtins.getEnv "NIXOS_STATE_VERSION" or "24.05";

  # Base Packages needed on all nodes
  environment.systemPackages = with pkgs; [
     htop vim git curl wget mtr netdata # Common utils
     k3s # Include k3s binary itself
  ];

  # Nix settings
  nix.settings.trusted-users = [ "root" "@wheel" (builtins.getEnv "ADMIN_USERNAME" or "nixos") ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
Test: nix-instantiate --parse ./k3s-cluster/profiles/base-server.nix.
[ ] 3.5: Create K3s Role Configurations (roles/)

Context: Defines the specific k3s service configurations for control-plane (server) and worker (agent) nodes, including crucial flags for Hetzner integration. Important: These modules should define the systemd service units but might not enable them if using the cloud-init role selector in the image build.
Implementation Detail:
k3s-control.nix:
Nix

# ./k3s-cluster/roles/k3s-control.nix
{ config, lib, pkgs, specialArgs, ... }:
let
  controlPlaneIp = builtins.getEnv "K3S_CONTROL_PLANE_ADDR" or "10.0.0.2";
  privateInterface = builtins.getEnv "HETZNER_PRIVATE_IFACE" or "eth1"; # Verify this!
in {
  # Define the k3s server service unit, but don't enable by default
  # Role selector service will enable it if role is 'control'
  systemd.services.k3s = {
     description = "Lightweight Kubernetes (Server)";
     wantedBy = [ "multi-user.target" ]; # Define dependencies if needed
     # ... other systemd unit options ...
     serviceConfig = {
         Type = "notify";
         ExecStart = "${pkgs.k3s}/bin/k3s server"; # Base command
     };
  };

  # Configure K3s via config file and flags
  services.k3s = {
    enable = false; # Let role-selector handle enabling
    role = "server";
    tokenFile = config.sops.secrets.k3s_token.path;
    extraFlags = toString [
      "--node-ip=${controlPlaneIp}"
      "--advertise-address=${controlPlaneIp}"
      "--bind-address=0.0.0.0" # Listen on all interfaces for LB/external access
      "--flannel-iface=${privateInterface}"
      "--kubelet-arg=cloud-provider=external"
      "--disable-cloud-controller"
      "--disable=servicelb,traefik" # Disable defaults we install manually
      # "--cluster-init" # Add this ONLY via extraModules for the FIRST node
    ];
    # Example of setting config via yaml
    # configYAML = pkgs.lib.generators.toYAML {} {
    #   "cluster-cidr" = "10.42.0.0/16";
    #   "service-cidr" = "10.43.0.0/16";
    # };
  };

  # Define the k3s token secret for sops-nix
  sops.secrets.k3s_token = { sopsFile = ../secrets/secrets.yaml; owner = "root"; group = "root"; mode = "0400"; };

  # Firewall rules for control plane
  networking.firewall.allowedTCPPorts = [ 6443 2379 2380 ]; # K8s API, etcd client, etcd peer
  networking.firewall.allowedUDPPorts = [ ]; # Flannel handled by worker rules or separate module

  # Add essential client tools
  environment.systemPackages = with pkgs; [ kubectl kubernetes-helm fluxcd ];
}
k3s-worker.nix:
Nix

# ./k3s-cluster/roles/k3s-worker.nix
{ config, lib, pkgs, specialArgs, ... }:
let
  # Use the same environment variable as in k3s-control.nix for consistency
  privateInterface = builtins.getEnv "HETZNER_PRIVATE_IFACE" or "eth1"; # Verify this!
in {
  # Define the k3s agent service unit
   systemd.services.k3s-agent = {
     description = "Lightweight Kubernetes (Agent)";
     wantedBy = [ "multi-user.target" ];
     # ... other systemd unit options ...
     serviceConfig = {
         Type = "notify";
         ExecStart = "${pkgs.k3s}/bin/k3s agent";
     };
   };

  # Configure K3s agent
  services.k3s = {
    enable = false; # Let role-selector handle enabling
    role = "agent";
    serverAddr = "https://${specialArgs.k3sControlPlaneAddr}:6443";
    tokenFile = config.sops.secrets.k3s_token.path;
    extraFlags = toString [
      # Let k3s auto-detect the node IP based on the interface
      # Using the same HETZNER_PRIVATE_IFACE variable as in k3s-control.nix
      "--flannel-iface=${privateInterface}" # Ensure CNI uses private net
      "--kubelet-arg=cloud-provider=external"
      # Add node labels here if consistent across all workers of this type
      # "--node-label=topology.kubernetes.io/zone=us-east-1a" # Example
    ];
  };

  # Define the k3s token secret for sops-nix
  sops.secrets.k3s_token = { sopsFile = ../secrets/secrets.yaml; owner = "root"; group = "root"; mode = "0400"; };

  # Worker firewall rules
  networking.firewall.allowedTCPPorts = [ 10250 ]; # Kubelet
  networking.firewall.allowedUDPPorts = [ 8472 51820 ]; # Flannel VXLAN / WireGuard

  # Add kubectl for debugging
  environment.systemPackages = with pkgs; [ kubectl ];
}
Test: nix-instantiate --parse ./k3s-cluster/roles/k3s-control.nix and ...k3s-worker.nix.
[ ] 3.6: Create Location Configurations (locations/)

Context: Environment-specific settings (Hetzner vs. Local).
Implementation Detail:
hetzner.nix: (From your Plan - Phase 3.6) Imports hetzner-hardware.nix, sets networking.primaryInterfaceDevice.name = "eth1"; (Verify!), enables services.cloud-init.
hetzner-hardware.nix: (From your Plan - Phase 3.6) Imports qemu-guest profile, sets bootloader, includes virtio/nvme modules from ${HETZNER_KERNEL_MODULES}.
local.nix: (From your Plan - Phase 3.6) Example setting different networking.nameservers.
Test: Parse individual location files.
[ ] 3.7: Create Hetzner Node Configuration (nodes/hetzner-k3s-node/default.nix)

Context: Defines the configuration baked into the generic Hetzner image, including the k3s-role-selector service for determining role via cloud-init.
Implementation Detail:
Nix

# ./k3s-cluster/nodes/hetzner-k3s-node/default.nix
# (Code from your Plan - Phase 3.7, adjusted for clarity)
{ config, lib, pkgs, specialArgs, ... }:
{
  imports = [
    # Base profile for common tools, SSH, Tailscale, Netdata, sops, etc.
    ../../profiles/base-server.nix
    # Hetzner specific hardware/network settings
    ../../locations/hetzner.nix
    # Import BOTH role modules - the selector service will enable the correct one
    ../../roles/k3s-control.nix
    ../../roles/k3s-worker.nix
  ];

  # Generic hostname for the image itself (will be overridden by cloud-init/actual server name)
  networking.hostName = "k3s-hetzner-node";

  # Ensure cloud-init is enabled to process user-data
  services.cloud-init.enable = true;

  # Systemd service to read role from cloud-init and enable correct k3s service
  systemd.services."k3s-role-selector" = {
    description = "Select k3s role based on cloud-init data (/etc/nixos/k3s_role)";
    wantedBy = [ "multi-user.target" ];
    # Run after cloud-init finishes and network is up
    after = [ "network-online.target" "cloud-final.service" ];
    # Ensure k3s services are defined before this tries to enable them
    requires = [ "k3s.service" "k3s-agent.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Script to read file and enable/disable services
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c '
          set -euo pipefail; ROLE_FILE="/etc/nixos/k3s_role"; ROLE="worker" # Default to worker
          if [ -f "$ROLE_FILE" ]; then ROLE=$(cat $ROLE_FILE); fi

          if [ "$ROLE" = "control" ]; then
            echo "Role selector: Enabling k3s server..."; systemctl enable --now k3s.service; systemctl disable --now k3s-agent.service || true;
          elif [ "$ROLE" = "worker" ]; then
            echo "Role selector: Enabling k3s agent..."; systemctl enable --now k3s-agent.service; systemctl disable --now k3s.service || true;
          else
            echo "Role selector: Unknown role [$ROLE] in $ROLE_FILE. Defaulting to worker." >&2; systemctl enable --now k3s-agent.service; systemctl disable --now k3s.service || true;
          fi
          echo "Role selector: Done."
        '';
    };
  };

  # Crucially: Ensure the role modules DO NOT enable k3s services by default
  # This is achieved by setting services.k3s.enable = false; inside roles/*.nix
  # The selector service will then enable the appropriate service based on the role.

  system.stateVersion = builtins.getEnv "NIXOS_STATE_VERSION" or "24.05";
}
Test: nix-instantiate --parse ./k3s-cluster/nodes/hetzner-k3s-node/default.nix.
[ ] 3.8: Create Installer Configuration (installer/default.nix)

Context: Defines the environment for the bootable USB installer for local machines.
Implementation Detail:
Nix

# ./k3s-cluster/installer/default.nix
# (Code from your Plan - Phase 3.8)
{ config, lib, pkgs, modulesPath, specialArgs, inputs, ... }: { # Added specialArgs/inputs for sops
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
     # Need sops module if installer uses secrets (e.g., Tailscale)
     inputs.sops-nix.nixosModules.sops
     # Optional: Include base profile for common tools/Tailscale in installer
     # ../profiles/base-server.nix # Be careful with dependencies
  ];
  environment.systemPackages = with pkgs; [ git vim curl wget parted gptfdisk disko k3s ];
  services.openssh.enable = true; # Enable SSH daemon
  services.openssh.settings.PermitRootLogin = "yes"; # Allow root login via SSH key
  users.users.root.initialPassword = ""; # Disable root password login
  users.users.root.openssh.authorizedKeys.keys = [ (builtins.getEnv "ADMIN_SSH_PUBLIC_KEY") ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = builtins.getEnv "NIXOS_STATE_VERSION" or "24.05";

  # If including Tailscale in installer:
  # services.tailscale = { enable = true; package = pkgs.tailscale; authKeyFile = config.sops.secrets.tailscale_authkey.path; };
  # sops.secrets.tailscale_authkey = { sopsFile = ../secrets/secrets.yaml; }; # Needs sops key on installer media or different handling
}
Test: nix-instantiate --parse ./k3s-cluster/installer/default.nix.
[ ] 3.9: Create Disko Configurations (modules/disko-*.nix)

Context: Declarative disk partitioning, useful for consistent local machine installs.
Implementation Detail: (Code from your Plan - Phase 3.9 for disko-control.nix and disko-worker.nix). Import these within the respective hardware-configs/*.nix files for local machines or use with disko script during installation.
Test: Parse the files.
[ ] 3.10: Create/Update Flake Configuration (./flake.nix)

Context: The main entrypoint defining inputs, outputs, node configurations using the builder, image/installer packages, and deploy-rs settings.
Implementation Detail: Ensure your main /home/evan/nixos/flake.nix integrates the k3s configurations correctly, referencing the files within ./k3s-cluster/. Use the detailed example provided in your plan (Phase 3.10) as a template, adjusting existing inputs/outputs as needed. Key parts: Define makeK3sNode let binding, k3sCommonSpecialArgs, nixosConfigurations for all Hetzner and local nodes using makeK3sNode, the k3s-node-cloud-builder and installer configs, packages outputs for hetznerK3sNodeImage & installerIso, and the deploy block using Tailscale hostnames.
Test: cd /home/evan/nixos && nix flake check . and nix flake show ..
Phase 4: Secrets Management (NixOS Bootstrap Secrets)
[ ] 4.1: Set Up Sops Configuration (./k3s-cluster/.sops.yaml)

Context: Configures sops to use your age key for encrypting secrets specific to the k3s NixOS configuration.
Implementation Detail:
YAML

# /home/evan/nixos/k3s-cluster/.sops.yaml
keys:
  - &admin ${builtins.getEnv "ADMIN_AGE_PUBLIC_KEY" or "age1p5v..."} # Use env var
creation_rules:
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
        - *admin
Test: File exists and is valid YAML.
[ ] 4.2: Create Secrets File (./k3s-cluster/secrets/secrets.yaml)

Context: This file will hold secrets needed by NixOS during build or bootstrap, encrypted with sops. K8s secrets (like Hetzner token for CCM/CSI, Harbor creds, app secrets) should generally be managed via Infisical or encrypted directly in the Flux repo.
Implementation Detail:
YAML

# /home/evan/nixos/k3s-cluster/secrets/secrets.yaml
# Add secrets needed by NixOS modules (imported via secrets.nix)
k3s_token: ENC[...] # Placeholder for encrypted token
tailscale_authkey: ENC[...] # Placeholder for encrypted key
# Add other NixOS-level secrets here if needed
sops:
  # ... metadata added by sops ...
Test: File exists.
[ ] 4.3: Encrypt K3s Token

Context: Encrypt the $K3S_TOKEN for use via sops-nix tokenFile.
Implementation Detail:
Bash

# Run from /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs directory
# Ensure secrets file exists with placeholders
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt # Or wherever your key is
sops --set '["k3s_token"] "'"$K3S_TOKEN"'"' ./k3s-cluster/secrets/secrets.yaml > ./k3s-cluster/secrets/secrets.yaml.new && \
  mv ./k3s-cluster/secrets/secrets.yaml.new ./k3s-cluster/secrets/secrets.yaml
Test: sops -d ./k3s-cluster/secrets/secrets.yaml | grep k3s_token shows the decrypted token.
[ ] 4.4: Encrypt Tailscale Auth Key

Context: Encrypt the $TAILSCALE_AUTH_KEY for use via sops-nix authKeyFile.
Implementation Detail:
Bash

# Run from /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs directory
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops --set '["tailscale_authkey"] "'"$TAILSCALE_AUTH_KEY"'"' ./k3s-cluster/secrets/secrets.yaml > ./k3s-cluster/secrets/secrets.yaml.new && \
  mv ./k3s-cluster/secrets/secrets.yaml.new ./k3s-cluster/secrets/secrets.yaml
Test: sops -d ./k3s-cluster/secrets/secrets.yaml | grep tailscale_authkey.
[ ] 4.5: Encrypt Hetzner API Token

Decision: Deferring this. The $HETZNER_TOKEN is primarily needed by Kubernetes components (CCM, CSI, CA), not NixOS itself. We will handle this secret within the Flux repository (encrypted via sops there) or potentially sync it via Infisical later.
[ ] 4.6: Configure Sops-Nix Integration (./k3s-cluster/secrets.nix)

Context: Tells NixOS modules how to access the decrypted secrets provided by sops-nix during evaluation/activation. Requires the age private key to be present on the target node at /var/lib/sops-nix/key.txt. Securely distributing this private key to nodes is critical and non-trivial. Options include baking it into a private image build (less secure), using deploy-rs secrets deployment feature, or another secure bootstrap mechanism.
Implementation Detail:
Nix

# ./k3s-cluster/secrets.nix
# (Code from your Plan - Phase 4.6)
{ config, lib, pkgs, ... }: {
  sops = {
    # IMPORTANT: Ensure the agent key is present on the target system at this path!
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Use SSH host key as identity? Requires setup.
    # age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ./secrets/secrets.yaml; # Relative to this file's location
    secrets = {
      k3s_token = {
         # Needed by roles/k3s-control.nix and roles/k3s-worker.nix
         owner = config.users.users.root.name; # k3s service runs as root
         group = config.users.groups.root.name;
         mode = "0400"; # Readable only by root
       };
      tailscale_authkey = {
         # Needed by modules/tailscale.nix
         owner = config.users.users.tailscaled.user;
         group = config.users.users.tailscaled.group;
         mode = "0400";
       };
      # Add other NixOS-level secrets here if defined in secrets.yaml
    };
  };
  # Ensure the key directory exists with correct permissions
  systemd.tmpfiles.rules = [
     "d /var/lib/sops-nix 0700 root root - -"
   ];
}
Test: nix-instantiate --parse ./k3s-cluster/secrets.nix. Runtime test requires the private key to be present on the node.

Phase 4: Secrets Management (NixOS Bootstrap Secrets)
Context: This phase configures sops and sops-nix to manage secrets required during the NixOS node build or bootstrap process. These typically include the shared K3s token and the Tailscale pre-authentication key. Secrets needed by Kubernetes applications (like API keys, database passwords, Hetzner token for K8s controllers) will be managed later via Infisical and its Kubernetes Operator (Phase 9).

[ ] 4.1: Set Up Sops Configuration

Context: Creates the .sops.yaml file within the ./k3s-cluster/ directory to configure SOPS specifically for the secrets used by the NixOS cluster configuration. It specifies your age public key (from $ADMIN_AGE_PUBLIC_KEY) as the recipient for encryption.
Implementation Detail: Create the file ./k3s-cluster/.sops.yaml:
YAML

# /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/k3s-cluster/.sops.yaml
keys:
  # Uses the age public key defined in flake's devShell shellHook (ensure it's correct!)
  - &admin ${ADMIN_AGE_PUBLIC_KEY:-age1p5vdpde60kwfjqeyufvp8xxtfk4ja39h42v4y26u8ju85ysw9y4qvuh0cd}
creation_rules:
  # Rule to automatically encrypt only the secrets.yaml file in the secrets/ subdir
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
        - *admin
Test: Verify file ./k3s-cluster/.sops.yaml exists and its content is valid YAML.
[ ] 4.2: Create Secrets File

Context: Creates the ./k3s-cluster/secrets/secrets.yaml file. This file will store the actual NixOS bootstrap secrets (key-value pairs) in an encrypted format. Initially, create it with placeholders.
Implementation Detail: Create the file with initial structure:
YAML

# /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/k3s-cluster/secrets/secrets.yaml
# Secrets needed during NixOS build/bootstrap phase ONLY
k3s_token: ENC[...] # Placeholder, encrypted in next step
tailscale_authkey: ENC[...] # Placeholder, encrypted in step 4.4
# Do NOT add K8s application secrets or Hetzner API token here.
sops:
  # SOPS metadata will be automatically generated/updated upon encryption.
  lastmodified: '...'
  mac: '...'
  version: '...'
  encrypted_regex: ^(data|stringData)$ # Default SOPS encryption pattern
  age: [] # Will be populated with recipient details on first encryption
Test: Verify file ./k3s-cluster/secrets/secrets.yaml exists and its content is valid YAML.
[ ] 4.3: Encrypt K3s Token

**Context**: Encrypts the K3s cluster join token ($K3S_TOKEN from .env) into the secrets.yaml file. This encrypted token will be accessed by the sops-nix module on nodes to configure the services.k3s.tokenFile. Ensure your age private key is available (e.g., via SOPS_AGE_KEY_FILE environment variable pointing to ~/.config/sops/age/keys.txt, or the key being present in that default location).

**Implementation Detail**: Use the sops CLI to add/update and encrypt the token:
Bash

# Run from NixOS Config Repo root: /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs
# Ensure K3S_TOKEN is exported via direnv from .env
# Ensure SOPS_AGE_KEY_FILE is set or private key is in ~/.config/sops/age/keys.txt
echo "Encrypting K3S_TOKEN into ./k3s-cluster/secrets/secrets.yaml..."
sops --set '["k3s_token"] "'"$K3S_TOKEN"'"' ./k3s-cluster/secrets/secrets.yaml > ./k3s-cluster/secrets/secrets.yaml.new && \
  mv ./k3s-cluster/secrets/secrets.yaml.new ./k3s-cluster/secrets/secrets.yaml
echo "K3S_TOKEN encrypted."
Test: Verify encryption using sops -d ./k3s-cluster/secrets/secrets.yaml | grep k3s_token. Commit the encrypted secrets.yaml to Git.
[ ] 4.4: Encrypt Tailscale Auth Key

**Context**: Encrypts the Tailscale authentication key ($TAILSCALE_AUTH_KEY from .env) into secrets.yaml. This allows nodes to automatically join your Tailnet on first boot via the sops-nix module configuring services.tailscale.authKeyFile. Use a reusable auth key from your Tailscale admin console, or generate an ephemeral key if preferred (nodes using ephemeral keys will be automatically removed after a period of inactivity).

**Implementation Detail**:
Bash

# Run from NixOS Config Repo root
# Ensure TAILSCALE_AUTH_KEY is exported via direnv from .env
# Ensure SOPS_AGE_KEY_FILE is set or private key is available
echo "Encrypting TAILSCALE_AUTH_KEY into ./k3s-cluster/secrets/secrets.yaml..."
sops --set '["tailscale_authkey"] "'"$TAILSCALE_AUTH_KEY"'"' ./k3s-cluster/secrets/secrets.yaml > ./k3s-cluster/secrets/secrets.yaml.new && \
  mv ./k3s-cluster/secrets/secrets.yaml.new ./k3s-cluster/secrets/secrets.yaml
echo "TAILSCALE_AUTH_KEY encrypted."
Test: Verify encryption using sops -d ./k3s-cluster/secrets/secrets.yaml | grep tailscale_authkey. Commit the encrypted secrets.yaml to Git.
[ ] 4.5: Encrypt Hetzner API Token

Context & Decision: The Hetzner API token ($HETZNER_TOKEN) is primarily needed by Kubernetes controllers deployed via Flux (CCM, CSI, Cluster Autoscaler). While it could be encrypted here, the best practice for K8s secrets is to manage them within the K8s ecosystem.
Implementation Detail: Deferring encryption. We will create a standard Kubernetes Secret containing this token directly within the Flux repository in Phase 9.1 (encrypting that manifest file with sops) or sync it from Infisical if preferred. Do not add $HETZNER_TOKEN to the NixOS ./k3s-cluster/secrets/secrets.yaml file.
[ ] 4.6: Configure Sops-Nix Integration

Context: This NixOS module (./k3s-cluster/secrets.nix) configures the sops-nix service on each node. It tells sops-nix where the encrypted secrets file is located within the Nix store (derived from defaultSopsFile) and, crucially, where to find the node's private age key (age.keyFile) for decryption during system activation. It defines which secrets from the file should be decrypted and placed into /run/secrets/ with specific ownership and permissions for consumption by other NixOS services (k3s, tailscale).
Security Warning: Securely distributing the private age key specified by sops.age.keyFile (e.g., /var/lib/sops-nix/key.txt) to each node is critical and outside the scope of sops-nix itself. Options include baking it into a truly private image build (less ideal), using deploy-rs's secret deployment feature, leveraging cloud-init securely, or manual placement during initial setup. Failure to provide the correct private key will prevent sops-nix from decrypting secrets, breaking services that depend on them.
Implementation Detail: Create ./k3s-cluster/secrets.nix:
Nix

# ./k3s-cluster/secrets.nix
{ config, lib, pkgs, ... }:
{
  sops = {
    # Path on the TARGET NODE where the PRIVATE age key is expected.
    # Ensure this key is securely provisioned!
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Alternative: Use SSH host key as identity (requires matching sops encryption rule)
    # age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Path to the encrypted secrets file, relative to this .nix file
    defaultSopsFile = ./secrets/secrets.yaml;

    # Define which secrets from the YAML file are needed by NixOS services
    secrets = {
      # Makes 'k3s_token' available at /run/secrets/k3s_token
      k3s_token = {
        # Needed by services.k3s in roles/{k3s-control.nix, k3s-worker.nix}
        owner = config.users.users.root.name; # k3s runs as root
        group = config.users.groups.root.name;
        mode = "0400"; # Read-only by root
      };
      # Makes 'tailscale_authkey' available at /run/secrets/tailscale_authkey
      tailscale_authkey = {
        # Needed by services.tailscale in modules/tailscale.nix
        owner = config.users.users.tailscaled.user; # Needs to be readable by tailscaled user
        group = config.users.users.tailscaled.group;
        mode = "0400"; # Read-only by tailscaled
      };
      # Add other secrets needed by NixOS modules here if they exist in secrets.yaml
    };
  };

  # Ensure the directory for the private age key exists with tight permissions
  # The key itself must be placed here by other means (e.g., deploy-rs).
  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0700 root root - -"
  ];
}
Test: Verify file syntax with nix-instantiate --parse ./k3s-cluster/secrets.nix. Runtime functionality relies on the private key existing at /var/lib/sops-nix/key.txt on the deployed nodes.

[ ] 4.7: Configure Deploy-rs for Private Key Distribution

Context: As recommended in the review, deploy-rs should be used to securely distribute the private age key to each node. This ensures the key is never stored in the Nix store and is securely transferred to the target nodes.

Implementation Detail: Add the following to your flake.nix to configure deploy-rs:

```nix
# In flake.nix, within the outputs section
deploy.nodes = {
  "hetzner-control-01" = {
    hostname = "hetzner-control-01";
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.hetzner-control-01;
      # Configure sops-nix private key deployment
      sshUser = "nixos"; # or ${ADMIN_USERNAME}
      secrets = {
        "sops-key" = {
          # Local path to the private key
          local = "${builtins.getEnv "HOME"}/.config/sops/age/keys.txt";
          # Remote path where the key should be placed
          remote = "/var/lib/sops-nix/key.txt";
          # Permissions for the key file
          permissions = "0400";
          # User and group that should own the key file
          user = "root";
          group = "root";
        };
      };
    };
  };
  
  # Similar configuration for worker nodes
  "hetzner-worker-static-01" = {
    hostname = "hetzner-worker-static-01";
    profiles.system = {
      user = "root";
      path = deploy-rs.lib.${system}.activate.nixos self.nixosConfigurations.hetzner-worker-static-01;
      sshUser = "nixos"; # or ${ADMIN_USERNAME}
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
  
  # Add more nodes as needed
};
```

Usage: After adding this configuration to your flake.nix, you can deploy the configuration and the private key to a node using:

```bash
deploy .#hetzner-control-01
```

This will securely copy the private key to the target node and then deploy the NixOS configuration. The key will be placed at /var/lib/sops-nix/key.txt with the correct permissions, allowing sops-nix to decrypt the secrets during system activation.

Test: Verify the configuration with `nix flake check` and test the deployment with `deploy .#hetzner-control-01 --dry-run`.

Phase 5: Hetzner Infrastructure Setup
Context: This phase uses the hcloud CLI (likely via just commands) to create the necessary cloud resources in your Hetzner project before provisioning nodes.

[ ] 5.1: Upload SSH Key to Hetzner

Context: Registers your ${ADMIN_SSH_PUBLIC_KEY} in Hetzner Cloud under the name ${HETZNER_SSH_KEY_NAME}, allowing SSH access to VMs created with this key.
Implementation Detail:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Uploading SSH key '${HETZNER_SSH_KEY_NAME:-my-admin-key}' to Hetzner..."
# Ensure ADMIN_SSH_PUBLIC_KEY and HETZNER_SSH_KEY_NAME are sourced
echo "$ADMIN_SSH_PUBLIC_KEY" | hcloud ssh-key create --name "${HETZNER_SSH_KEY_NAME:-my-admin-key}" --public-key-from-stdin
Test: hcloud ssh-key list shows the key.
[ ] 5.2: Create Private Network

Context: Creates the isolated network (${PRIVATE_NETWORK_NAME}) with the 10.0.0.0/16 range and adds a subnet specific to your Hetzner location (${HETZNER_NETWORK_ZONE} or default us-east) for server attachment. This network is crucial for secure and efficient k3s communication.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Creating Hetzner private network '${PRIVATE_NETWORK_NAME:-k3s-net}'..."
just create-hetzner-network # Just command includes subnet creation
Test: hcloud network describe ${PRIVATE_NETWORK_NAME:-k3s-net} shows details.
[ ] 5.3: Create Firewall

Context: Creates the Hetzner Cloud Firewall (${FIREWALL_NAME}) and applies the necessary inbound rules to allow traffic for SSH (from admin), K8s API (from admin/private net), Kubelet (from private net), CNI (Flannel default ports from private net), Etcd (for future HA, from private net), and Ingress (Traefik ports, initially open). Uses ${ADMIN_PUBLIC_IP}.
Implementation Detail: Use the just command (ensure the justfile definition includes all necessary ports):
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Creating Hetzner firewall '${FIREWALL_NAME:-k3s-fw}' and adding rules..."
just create-hetzner-firewall
Test: hcloud firewall describe ${FIREWALL_NAME:-k3s-fw} shows the firewall and verify all expected rules are present.
[ ] 5.4: Create Placement Group (Optional)

Context: Creates a 'spread' placement group (${PLACEMENT_GROUP_NAME}) to encourage Hetzner to place your VMs on different underlying physical hosts, improving resilience. Optional but recommended.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Creating Hetzner placement group '${PLACEMENT_GROUP_NAME:-k3s-placement-group}'..."
just create-hetzner-placement-group
Test: hcloud placement-group list shows the group.
Phase 6: Build and Upload Hetzner Image
Context: This phase builds the generic NixOS node image using your flake configuration and uploads it for use by Hetzner Cloud. Leverage CI/CD (GitHub Actions) for automation.

[ ] 6.1: Build Hetzner Image

Context: Compiles the k3s-node-cloud-builder NixOS configuration from your flake into a bootable disk.raw file.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Building Hetzner K3s Node Image (Flake Output: hetznerK3sNodeImage)..."
# The just command runs: nix build .#hetznerK3sNodeImage --impure
just build-k3s-image
Test: Check for result/disk.raw in the repo root. Verify build logs for errors.
[ ] 6.2: Compress Image

Context: Reduces the raw image size using zstd for efficient uploading.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Compressing image artifact..."
# The just command runs: zstd result/disk.raw -o hetzner-k3s-image.zst
just compress-k3s-image
Test: Check for hetzner-k3s-image.zst in the repo root. Note its size.
[ ] 6.3: Upload Image

Context: Host the compressed image (.zst) publicly via HTTPS so Hetzner can download it. GitHub Releases is a common method for project artifacts. Crucially, Hetzner needs a direct download link.
Implementation Detail (Example using GitHub CLI - adapt for your CI/CD):
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
TAG_NAME="k3s-image-$(date +%Y%m%d%H%M%S)"
GITHUB_REPO_FULL="${GITHUB_USER}/${FLUX_REPO}" # Assuming Flux repo used for releases, adjust if using NixOS repo
echo "Creating GitHub release $TAG_NAME in $GITHUB_REPO_FULL..."
gh release create "$TAG_NAME" --repo "$GITHUB_REPO_FULL" \
    --notes "NixOS K3s image build for Hetzner - ${TAG_NAME}" \
    ./hetzner-k3s-image.zst # Upload in one step
echo "Verifying upload..."
# Verify direct download URL (structure might change, TEST THIS LINK!)
IMAGE_DOWNLOAD_URL="https://github.com/$GITHUB_REPO_FULL/releases/download/$TAG_NAME/hetzner-k3s-image.zst"
echo "Potential Direct Download URL: $IMAGE_DOWNLOAD_URL"
echo "Testing download URL with curl..."
if curl --output /dev/null --silent --head --fail "$IMAGE_DOWNLOAD_URL"; then
  echo "URL appears valid."
  # Export for next step if running interactively
  export IMAGE_DOWNLOAD_URL
else
  echo "Error: URL $IMAGE_DOWNLOAD_URL may not be directly downloadable by Hetzner." >&2
  echo "Consider using a different hosting method (e.g., public S3 bucket) or finding the correct direct asset URL." >&2
  # exit 1 # Optionally exit if URL is invalid
fi
Test: Verify the release exists on GitHub. Manually test the ${IMAGE_DOWNLOAD_URL} with curl -L -o /dev/null <URL> to ensure it triggers a direct download.
[ ] 6.4: Register Image in Hetzner

Context: Submits the image download URL to Hetzner Cloud, which downloads, decompresses (it handles .zst), and registers it as a custom snapshot/image under the name ${HETZNER_IMAGE_NAME}.
Implementation Detail: Use the just command with the verified URL:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
if [ -z "$IMAGE_DOWNLOAD_URL" ]; then echo "Error: IMAGE_DOWNLOAD_URL not set/exported." >&2; exit 1; fi
echo "Registering image '${HETZNER_IMAGE_NAME:-my-k3s-image-v1}' in Hetzner from $IMAGE_DOWNLOAD_URL..."
# The just command runs: hcloud image create --name ... --url ...
just register-k3s-image "$IMAGE_DOWNLOAD_URL"
Test: hcloud image list should show the new image. Wait for its status to become available. Note its final ID or name if different from ${HETZNER_IMAGE_NAME}. Update the HETZNER_IMAGE_NAME variable in your flake's devShell shellHook if needed for future steps.
Phase 7: Node Provisioning
Context: Create the actual Hetzner virtual machines using the registered NixOS image, attaching them to the network/firewall, applying labels, and passing cloud-init user-data to specify the node role.

[ ] 7.1: Provision Control Plane Node (hetzner-control-01)

Context: Creates the initial master node. Uses ${HETZNER_IMAGE_NAME}, ${CONTROL_PLANE_VM_TYPE}, ${HETZNER_LOCATION}, ${HETZNER_SSH_KEY_NAME}, ${PRIVATE_NETWORK_NAME}, ${FIREWALL_NAME}, ${PLACEMENT_GROUP_NAME}. Sets labels k8s-cluster, k8s-nodepool=control-plane. Passes user-data to set role to control.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Provisioning control plane node 'hetzner-control-01'..."
just create-control-node
Test: hcloud server list --selector k8s-nodepool=control-plane shows the server provisioning and then running. hcloud server describe hetzner-control-01 shows correct labels, network, firewall attachment.
[ ] 7.2: Wait for Control Plane Node to Boot

Context: Allow time for the VM boot process, cloud-init execution, NixOS activation, and network initialization (including Tailscale).
Implementation Detail: Monitor status and test SSH connectivity:
Bash

# Run from local machine
CONTROL_NODE_NAME="hetzner-control-01"
CONTROL_NODE_IP=$(hcloud server ip $CONTROL_NODE_NAME)
ADMIN_USER=${ADMIN_USERNAME:-nixos}
echo "Waiting for $CONTROL_NODE_NAME ($CONTROL_NODE_IP) to become SSH reachable as $ADMIN_USER..."
until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $ADMIN_USER@$CONTROL_NODE_IP "echo 'SSH OK'" &>/dev/null; do
  echo -n "." && sleep 5
done
echo " SSH OK."
# Optionally add a Tailscale status check here if needed immediately
Test: Successful SSH login: ssh $ADMIN_USER@$CONTROL_NODE_IP.
[ ] 7.3: Verify K3s Server is Running

Context: Log into the node and confirm the k3s-role-selector service correctly identified the 'control' role and started the k3s.service. Then fetch the kubeconfig.
Implementation Detail:
Bash

# Run from local machine
CONTROL_IP=$(hcloud server ip hetzner-control-01)
ADMIN_USER=${ADMIN_USERNAME:-nixos}
echo "Verifying k3s server status on $CONTROL_NODE_NAME..."
ssh $ADMIN_USER@$CONTROL_IP "sudo systemctl status k3s-role-selector.service"
ssh $ADMIN_USER@$CONTROL_IP "sudo systemctl status k3s.service"
ssh $ADMIN_USER@$CONTROL_IP "sudo journalctl -u k3s-role-selector --no-pager -n 20" # Check logs
echo "Waiting for K3s API on node to stabilize..."
until ssh $ADMIN_USER@$CONTROL_IP "sudo kubectl get node $CONTROL_NODE_NAME" &>/dev/null; do sleep 5 && echo -n "."; done; echo " API OK on node."
echo "Fetching kubeconfig..."
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
just get-kubeconfig # Saves to ~/.kube/config.k3s
export KUBECONFIG=~/.kube/config.k3s
echo "Verifying node $CONTROL_NODE_NAME is Ready in cluster..."
kubectl wait --for=condition=Ready node/$CONTROL_NODE_NAME --timeout=5m
Test: systemctl status k3s.service shows active (running). kubectl get node hetzner-control-01 -o wide shows Ready status.
[ ] 7.4: Note Control Plane Private IP

Context: Confirm the actual private IP matches ${K3S_CONTROL_PLANE_ADDR} used in NixOS configs.
Implementation Detail:
Bash

# Run from local machine
HCLOUD_PRIVATE_IP=$(hcloud server describe hetzner-control-01 -o json | jq -r '.private_net[0].ip')
CONFIG_PRIVATE_IP=${K3S_CONTROL_PLANE_ADDR:-10.0.0.2} # Get from env var used by Nix
echo "Hetzner Assigned Private IP: $HCLOUD_PRIVATE_IP"
echo "Configured Control Plane IP: $CONFIG_PRIVATE_IP"
if [ "$HCLOUD_PRIVATE_IP" != "$CONFIG_PRIVATE_IP" ]; then
  echo "WARNING: IPs differ! Ensure NixOS config (flake specialArgs, roles) uses $HCLOUD_PRIVATE_IP if dynamic." >&2
fi
Test: IPs match, or discrepancy is understood.
[ ] 7.5: Provision Initial Worker Node (hetzner-worker-static-01)

Context: Creates the first worker node using the same image but with cloud-init setting role to worker. Applies k8s-nodepool=static-workers label. Uses ${WORKER_VM_TYPE}.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Provisioning static worker node 'hetzner-worker-static-01'..."
# Creates hetzner-worker-static-workers-1 with default type WORKER_VM_TYPE
just create-worker-node 1 pool="static-workers"
Test: hcloud server list --selector k8s-nodepool=static-workers.
[ ] 7.6: Wait for Worker Node to Boot

Context: Allow time for boot, cloud-init, NixOS activation, Tailscale, and k3s-agent start.
Implementation Detail: Monitor status and test SSH:
Bash

WORKER_NODE_NAME="hetzner-worker-static-workers-1" # Matches default just command naming
WORKER_NODE_IP=$(hcloud server ip $WORKER_NODE_NAME)
ADMIN_USER=${ADMIN_USERNAME:-nixos}
echo "Waiting for $WORKER_NODE_NAME ($WORKER_NODE_IP) to become SSH reachable as $ADMIN_USER..."
until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $ADMIN_USER@$WORKER_NODE_IP "echo 'SSH OK'" &>/dev/null; do
  echo -n "." && sleep 5
done
echo " SSH OK."
Test: Successful SSH login: ssh $ADMIN_USER@$WORKER_NODE_IP.
[ ] 7.7: Verify Worker Node Joins Cluster

Context: The k3s agent service (enabled by the role selector reading worker from cloud-init) should connect to the serverAddr (${K3S_CONTROL_PLANE_ADDR}) using the shared tokenFile.
Implementation Detail:
Bash

# Run from local machine
export KUBECONFIG=~/.kube/config.k3s
WORKER_NODE_NAME="hetzner-worker-static-workers-1"
echo "Waiting for worker node '$WORKER_NODE_NAME' to appear in kubectl..."
until kubectl get node $WORKER_NODE_NAME &>/dev/null; do sleep 5 && echo -n "."; done; echo " Node Found."
echo "Waiting for node '$WORKER_NODE_NAME' to be Ready..."
kubectl wait --for=condition=Ready node/$WORKER_NODE_NAME --timeout=5m
Test: kubectl get nodes -o wide shows both nodes with correct roles and Ready status.
Phase 8: Flux Setup and GitOps Configuration
Context: Install FluxCD controllers into the cluster and configure them to synchronize the Kubernetes manifests defined in your Flux Git repository (!kube-flux/clusters/hetzner/). Enable SOPS decryption for managing secrets-in-Git.

[ ] 8.1: Configure Kubernetes Access

Context: Ensure kubectl locally points to the new Hetzner k3s cluster.
Implementation Detail:
Bash

# Ensure KUBECONFIG is set (from step 7.3)
export KUBECONFIG=~/.kube/config.k3s
echo "Current Kubeconfig Context:"
kubectl config current-context
echo "Cluster Nodes:"
kubectl get nodes
Test: Commands execute successfully without errors.
[ ] 8.2: Prepare Existing Flux Repository (!kube-flux)

Context: Confirm the target path (clusters/hetzner/) and subdirectories for component categories exist in your Git repo branch.
Implementation Detail: (Ensure steps from 2.2 were completed). Verify structure:
Bash

ls -d /home/evan/2_Dev/2.1_Homelab/\!kube-flux/clusters/hetzner/*/
Test: Expected subdirectories (core, infrastructure, apps, observability, etc.) are listed.
[ ] 8.3: Bootstrap Flux

Context: Installs Flux controllers (source-controller, kustomize-controller, helm-controller, notification-controller) into the flux-system namespace and creates the initial GitRepository source and Kustomization pointing to your repo/path. Requires GitHub credentials.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
# Ensure GITHUB_USER, GITHUB_TOKEN, FLUX_REPO env vars are sourced
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Bootstrapping Flux..."
just bootstrap-flux
Test: kubectl get pods -n flux-system. All Flux pods should eventually be Running. Check flux check --kubeconfig=$KUBECONFIG reports success. Verify resources: flux get sources git -A, flux get kustomizations -A.
[ ] 8.4: Configure Flux SOPS Integration

Context: Provides Flux controllers with your private age key so they can decrypt SOPS-encrypted manifests fetched from Git. The private key is stored securely as a Kubernetes secret.
Implementation Detail:
Create K8s Secret sops-age:
Bash

# Run from local machine where AGE_PRIVATE_KEY is available and secure
if [ -z "$AGE_PRIVATE_KEY" ]; then echo "Error: AGE_PRIVATE_KEY env var not set." >&2; exit 1; fi
echo "Creating K8s secret 'sops-age' in 'flux-system' namespace..."
echo -n "$AGE_PRIVATE_KEY" | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin
# Verify secret creation immediately (don't leave key in history or temp files)
kubectl get secret sops-age -n flux-system
Configure Main Flux Kustomization: Add the decryption block to the flux-system Kustomization created by bootstrap. Edit the file !kube-flux/clusters/hetzner/flux-system/gotk-sync.yaml (or similar name) in your Flux repo:
YAML

# !kube-flux/clusters/hetzner/flux-system/gotk-sync.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system # Name usually set by bootstrap
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/hetzner # Path monitored by this Kustomization
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system # Source defined by bootstrap
  # Add this decryption block:
  decryption:
    provider: sops
    secretRef:
      name: sops-age # Points to the K8s secret holding the private key
  # Ensure this Kustomization has appropriate health checks if needed
  # healthChecks: ...
  timeout: 5m
  # ... other existing spec fields ...
Commit and push this change to your Flux repository.
Test: After Flux reconciles the updated Kustomization, deploy a simple SOPS-encrypted ConfigMap later in Phase 9 and verify it gets created correctly. Monitor Flux logs (flux logs --level=error -n flux-system) for decryption errors.
[ ] 8.5+: Create Flux Kustomizations (Hierarchy)

Context: Defines the deployment order and structure for all cluster components within the Flux repository, using Kustomization CRDs that point to specific subdirectories and declare dependencies.

Implementation Detail: In the Flux repo path /home/evan/2_Dev/2.1_Homelab/!kube-flux/clusters/hetzner/, create the following top-level Kustomization YAML files:

core.yaml: Points to ./core, no dependsOn. Contains Namespace resources.
infrastructure.yaml: Points to ./infrastructure, dependsOn: [name: core]. Contains CCM, CSI, SUC, CA, Hetzner Secret.
secrets-sync.yaml: Points to ./secrets-sync, dependsOn: [name: core, name: infrastructure]. Contains Infisical Operator, InfisicalSecret CRDs.
registry.yaml: Points to ./registry, dependsOn: [name: infrastructure, name: secrets-sync]. Contains Harbor HelmRelease.
apps.yaml: Points to ./apps, dependsOn: [name: infrastructure, name: secrets-sync, name: registry]. Contains Traefik, Cert-Manager, ClusterIssuers, Middleware, basic app manifests.
observability.yaml: Points to ./observability, dependsOn: [name: infrastructure, name: apps]. Contains Otel/FluentBit Collector, Grafana, Pixie.
security.yaml: Points to ./security, dependsOn: [name: infrastructure]. Contains Falco, Kyverno, Kyverno policies.
delivery.yaml: Points to ./delivery, dependsOn: [name: infrastructure, name: apps]. Contains Flagger.
backup.yaml: Points to ./backup, dependsOn: [name: infrastructure, name: secrets-sync]. Contains Velero, BackupStorageLocation, Schedules, MinIO secret (synced via Infisical or SOPS).
Example infrastructure.yaml:

YAML

# !kube-flux/clusters/hetzner/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure # This name is used in dependsOn
  namespace: flux-system
spec:
  interval: 10m # How often to check Git for changes
  path: ./clusters/hetzner/infrastructure # Directory containing manifests for this layer
  prune: true # Delete resources removed from Git
  sourceRef:
    kind: GitRepository
    name: flux-system # The Git source defined by bootstrap
  dependsOn:
    - name: core # Ensure core namespaces exist first
  timeout: 5m # Max time for reconciliation
  healthChecks: # Optional: Ensure components become ready
    - apiVersion: apps/v1
      kind: DaemonSet
      name: hcloud-csi-node
      namespace: kube-system
    - apiVersion: apps/v1
      kind: Deployment
      name: hcloud-cloud-controller-manager
      namespace: kube-system
    - apiVersion: apps/v1
      kind: Deployment
      name: cluster-autoscaler
      namespace: kube-system
Create corresponding kustomization.yaml files inside each subdirectory (e.g., ./infrastructure/kustomization.yaml) listing the HelmRelease/YAML files within that directory.

Test: Commit the Kustomization CRs structure to Git. Verify using flux get kustomizations -A. Check their dependencies and ready status. They will likely wait for manifests to be added to the subdirectories in the next phase.

Okay, here is the final part (Phases 9-12 and beyond) of the comprehensive guide, augmented with the detailed code examples, tool configurations, operational practices, and future considerations we discussed. It follows your provided structure and uses the correct paths relative to your specified NixOS and Flux repositories.

(Continuing from Phase 8)

(NixOS Repo Root: /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs)
(Flux Repo Root: /home/evan/2_Dev/2.1_Homelab/!kube-flux)
(Paths below are relative to the Flux Repo Root unless specified)

Phase 9: Cluster Add-ons Deployment (via Flux)
Context: This phase defines the Kubernetes manifests (primarily HelmRelease and supporting resources like HelmRepository, Secret, CRDs) within your Flux repository (clusters/hetzner/ subdirectories) to deploy and configure all the chosen cluster components. FluxCD will automatically reconcile these manifests.

[ ] 9.1: Create Hetzner API Secret (for K8s Controllers)

Context: Provides the Hetzner API token ($HETZNER_TOKEN) as a Kubernetes Secret for use by CCM, CSI, and Cluster Autoscaler. This manifest is encrypted using sops and decrypted by Flux.
Implementation Detail: Create and encrypt clusters/hetzner/infrastructure/hcloud-secret.yaml:
Bash

# Create the secret file content (ensure vars are sourced)
cat > "/tmp/hcloud-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: hcloud # Name referenced by CCM/CSI/CA HelmReleases
  namespace: kube-system # Common namespace for infrastructure secrets
stringData:
  # Keys expected by the Helm charts
  token: ${HETZNER_TOKEN}
  network: ${PRIVATE_NETWORK_NAME:-k3s-net}
EOF

# Encrypt the secret file using sops and your age key
# Ensure SOPS_AGE_KEY_FILE is set or key is in ~/.config/sops/age/keys.txt
sops --encrypt --in-place "/tmp/hcloud-secret.yaml"

# Move the encrypted file to the Flux repository infrastructure directory
mv "/tmp/hcloud-secret.yaml" "/home/evan/2_Dev/2.1_Homelab/!kube-flux/clusters/hetzner/infrastructure/hcloud-secret.yaml"

# Add to the infrastructure kustomization
# Ensure infrastructure/kustomization.yaml lists hcloud-secret.yaml

# Commit and push changes to the Flux repo
cd "/home/evan/2_Dev/2.1_Homelab/!kube-flux"
git add clusters/hetzner/infrastructure/hcloud-secret.yaml clusters/hetzner/infrastructure/kustomization.yaml
git commit -m "feat(hetzner/infra): Add SOPS-encrypted Hetzner API secret"
# git push origin hetzner-cluster
Test: After Flux syncs: kubectl get secret hcloud -n kube-system. Verify Flux controller logs show successful decryption and application.
[ ] 9.2: Deploy Hetzner Cloud Controller Manager (CCM)

Context: Integrates K8s with Hetzner API for LoadBalancer services and node lifecycle management. Uses the hcloud secret.
Implementation Detail: Create clusters/hetzner/infrastructure/hcloud-ccm.yaml:
YAML

# clusters/hetzner/infrastructure/hcloud-ccm.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: hetzner # Name used in HelmRelease sourceRef
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.hetzner.cloud
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: hcloud-ccm # HelmRelease name
  namespace: kube-system # Deploy into kube-system
spec:
  interval: 15m
  chart:
    spec:
      chart: hcloud-cloud-controller-manager
      version: "1.18.0" # Specify a stable version (check latest)
      sourceRef:
        kind: HelmRepository
        name: hetzner # Matches HelmRepository above
        namespace: flux-system
  values:
    # Reference the K8s secret created in step 9.1
    hcloud:
      secretName: hcloud
    # Enable networking features if using Hetzner networks/routes directly
    networking:
      enabled: true
    # Important: Set your cluster CIDR if different from k3s default
    # clusterCIDR: "10.42.0.0/16"
Test: After Flux syncs: kubectl get pods -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager. Check logs for successful connection using the secret.
[ ] 9.3: Deploy Hetzner CSI Driver

Context: Enables provisioning of PersistentVolumes using Hetzner Block Storage. Uses the hcloud secret. Sets hcloud-volumes as the default StorageClass.
Implementation Detail: Create clusters/hetzner/infrastructure/hcloud-csi.yaml:
YAML

# clusters/hetzner/infrastructure/hcloud-csi.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: hcloud-csi
  namespace: kube-system
spec:
  interval: 15m
  chart:
    spec:
      chart: hcloud-csi
      version: "1.11.1" # Specify a stable version
      sourceRef:
        kind: HelmRepository
        name: hetzner # Assumes repo defined in hcloud-ccm.yaml or globally
        namespace: flux-system
  values:
    # Reference the K8s secret containing the Hetzner token
    controller:
      hcloudTokenSecretRef: # Use this structure for newer chart versions
        name: hcloud
        key: token
      # Optional: Set default volume options
      # defaultVolumeFsType: ext4
    storageClasses:
      # Define the default storage class
      - name: hcloud-volumes
        defaultStorageClass: true
        reclaimPolicy: Delete # Or Retain
        volumeBindingMode: WaitForFirstConsumer
    # Enable volume expansion if needed
    # controller:
    #   featureGates: "ExpandCSIVolumes=true"
    # node:
    #   featureGates: "ExpandCSIVolumes=true"
Test: kubectl get pods -n kube-system -l app.kubernetes.io/name=hcloud-csi. kubectl get sc shows hcloud-volumes (default). Test PVC creation later (Phase 12.3).
[ ] 9.4: Deploy System Upgrade Controller (SUC)

Context: Manages automated k3s upgrades via Plan CRDs. Deployed into system-upgrade namespace.
Implementation Detail: Create clusters/hetzner/infrastructure/system-upgrade-controller.yaml:
YAML

# clusters/hetzner/infrastructure/system-upgrade-controller.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: system-upgrade
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: system-upgrade-controller-repo # Source repo name
  namespace: flux-system
spec:
  interval: 1h
  url: https://github.com/rancher/system-upgrade-controller.git
  ref:
    tag: v0.13.4 # Use a specific, recent tag
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: system-upgrade-controller # Kustomization applying the manifests
  namespace: flux-system
spec:
  interval: 1h
  path: ./manifests # Path within the GitRepository source
  prune: true
  sourceRef:
    kind: GitRepository
    name: system-upgrade-controller-repo # Matches GitRepository above
  targetNamespace: system-upgrade # Deploy into this namespace
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: system-upgrade-controller
      namespace: system-upgrade
Test: kubectl get pods -n system-upgrade -l app=system-upgrade-controller. Check CRDs: kubectl get crd plans.upgrade.cattle.io.
[ ] 9.5: Deploy Cluster Autoscaler (CA)

Context: Automatically adjusts the number of worker nodes in designated pools based on pod scheduling pressure. Requires Hetzner provider config and API token.
Implementation Detail: Create clusters/hetzner/infrastructure/cluster-autoscaler.yaml:
YAML

# clusters/hetzner/infrastructure/cluster-autoscaler.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: autoscaler # Source repo name
  namespace: flux-system
spec:
  interval: 1h
  url: https://kubernetes.github.io/autoscaler
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cluster-autoscaler
  namespace: kube-system # Deploy into kube-system
spec:
  interval: 15m
  chart:
    spec:
      chart: cluster-autoscaler
      # Find the latest compatible 9.x version supporting hetzner provider
      version: "9.34.0" # Example version, check compatibility!
      sourceRef:
        kind: HelmRepository
        name: autoscaler
        namespace: flux-system
  values:
    autoDiscovery:
      clusterName: ${K3S_CLUSTER_NAME:-k3s-us-east} # Use your cluster name label
      # Use labels to identify node pools instead of explicit cloudprovider config nodes:
      # See chart docs for auto-discovery based on labels
      # Alternatively, define node groups explicitly:
      # nodeGroupAutoDiscovery:
      #   # Example: Discover based on the labels applied by hcloud create
      #   labelSelector: "k8s-cluster=${K3S_CLUSTER_NAME:-k3s-us-east}, k8s-nodepool"

    # Required configuration for Hetzner provider
    cloudProvider: hetzner
    hetznerCloudController: # This structure might vary based on chart version
       tokenSecretRef: # Reference the K8s secret directly
         name: hcloud
         key: token
       networkName: ${PRIVATE_NETWORK_NAME:-k3s-net}

    # Node Group definition (if not using auto-discovery based on labels)
    # This tells CA which nodes to manage. Match labels applied in Phase 7!
    # nodeGroups:
    #   - name: autoscaled-workers # Arbitrary name
    #     minSize: 1
    #     maxSize: 5 # Example limits
    #     labels:
    #       k8s-nodepool: autoscaled-workers # Label applied to these VMs
    #     instanceType: ${WORKER_VM_TYPE:-cpx21} # Type CA should create
    #     region: ${HETZNER_LOCATION:-ash} # Location for new nodes
    #     # Add other pools as needed

    # Fine-tuning autoscaler behavior
    extraArgs:
      # Use this if using explicit nodeGroups definition above
      # nodes: "1:5:k8s-nodepool=autoscaled-workers" # min:max:label (redundant if nodeGroups used)
      # General tuning:
      expander: random # Or least-waste, priority
      scale-down-delay-after-add: 5m
      scale-down-unneeded-time: 5m
      skip-nodes-with-local-storage: false # Important if using local PVs
      balance-similar-node-groups: true
      # v: 4 # Increase log verbosity for debugging

    rbac:
      create: true
    serviceMonitor: # Disable if not using Prometheus Operator's ServiceMonitors
      enabled: false
Test: kubectl get pods -n kube-system -l app.kubernetes.io/name=cluster-autoscaler. Check logs (kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler -f) for successful Hetzner connection and node group detection/parsing.
[ ] 9.6: Deploy Traefik (Ingress Controller)

Context: Manages external access to cluster services, handles routing, and integrates with Tailscale and Cert-Manager.
Implementation Detail: Create clusters/hetzner/apps/traefik.yaml:
YAML

# clusters/hetzner/apps/traefik.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: traefik-system
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: traefik # Source repo name
  namespace: flux-system
spec:
  interval: 1h
  url: https://helm.traefik.io/traefik
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik-system # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: traefik
      version: "26.1.0" # Specify a stable version (check latest v26+)
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: flux-system
  values:
    # Enable CRDs (IngressRoute, Middleware etc.)
    providers:
      kubernetesCRD:
        enabled: true
      kubernetesIngress:
        enabled: true # Can disable if ONLY using IngressRoute CRDs

    # Configure entrypoints (web = HTTP, websecure = HTTPS)
    ports:
      web:
        port: 8000 # Internal container port
        expose: true
        exposedPort: 80 # External port on host/LB
        protocol: TCP
      websecure:
        port: 8443
        expose: true
        exposedPort: 443
        protocol: TCP
        # Enable TLS by default for websecure
        tls:
          enabled: true
          # Reference Tailscale resolver for *.ts.net domains
          certResolver: tailscaleresolver
          # Optional: Define default domains for TLS
          # domains:
          #   - main: "your-primary-domain.com"
          #     sans:
          #       - "*.your-primary-domain.com"

    # Enable Tailscale certificate resolver
    additionalArguments:
      - "--certificatesresolvers.tailscaleresolver.tailscale={}"
      # Enable access logs (JSON recommended for collectors)
      - "--accesslog=true"
      - "--accesslog.format=json"
      # Enable Prometheus metrics endpoint
      - "--metrics.prometheus=true"
      - "--metrics.prometheus.entrypoint=metrics"
      # Enable Tracing (OTLP -> SigNoz) - requires OTel Collector address
      - "--tracing.opentelemetry=true"
      # Example: assumes collector service in 'monitoring' namespace
      - "--tracing.opentelemetry.address=opentelemetry-collector.monitoring.svc.cluster.local:4317"
      # Optional: Enable dashboard (secure it with middleware!)
      - "--api.dashboard=true"
      - "--api.insecure=false" # Do NOT expose insecurely

    # Add metrics entrypoint if not default
    # ports:
    #   metrics:
    #     port: 9100
    #     expose: false # Usually not exposed externally

    # Service annotations for Hetzner Load Balancer if exposing Traefik that way
    service:
      enabled: true
      type: LoadBalancer # Or NodePort if preferred
      annotations:
        # Required annotations for Hetzner LB service
        load-balancer.hetzner.cloud/location: ${HETZNER_LOCATION:-ash}
        load-balancer.hetzner.cloud/use-private-ip: "true" # Route LB -> Node via private net
        load-balancer.hetzner.cloud/name: "${K3S_CLUSTER_NAME:-k3s}-traefik-lb"
        # Recommended for preserving client IP (requires Traefik config too)
        load-balancer.hetzner.cloud/uses-proxyprotocol: "true"
      # Optional: Specify LB type
      # load-balancer.hetzner.cloud/type: lb11

    # Enable Proxy Protocol if using LB annotation above
    # ports:
    #   web:
    #     proxyProtocol:
    #       trustedIPs: [...] # Add Hetzner LB Source IPs
    #   websecure:
    #     proxyProtocol:
    #       trustedIPs: [...]
Test: kubectl get pods,svc -n traefik-system. Check Hetzner console for Load Balancer creation if type: LoadBalancer used. Access dashboard (requires further ingress/auth setup).
[ ] 9.7: Deploy Cert-Manager

Context: Manages TLS certificate lifecycles within Kubernetes, crucial for automating HTTPS.
Implementation Detail: Create clusters/hetzner/apps/cert-manager.yaml:
YAML

# clusters/hetzner/apps/cert-manager.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: jetstack # Source repo name
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: cert-manager
      version: "v1.14.5" # Specify a stable version
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
  # CRDs must be installed BEFORE the HelmRelease tries to use them
  # The chart handles this if installCRDs=true
  values:
    installCRDs: true
    # Optional: configure resources, Prometheus scraping etc.
    # prometheus:
    #   enabled: true
    #   servicemonitor:
    #     enabled: true
Test: kubectl get pods -n cert-manager. kubectl get crds | grep cert-manager.io.
[ ] 9.8: Configure ClusterIssuer

Context: Defines how Cert-Manager obtains certificates cluster-wide, typically using Let's Encrypt ACME protocol. Uses Traefik for the HTTP01 challenge.
Implementation Detail: Create clusters/hetzner/apps/cluster-issuer.yaml:
YAML

# clusters/hetzner/apps/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  # Name referenced in IngressRoute/Ingress annotations
  name: letsencrypt-prod
spec:
  acme:
    # Email address for important ACME account notifications
    email: ${ACME_EMAIL_ADDRESS} # Use variable from flake's devShell shellHook
    server: https://acme-v02.api.letsencrypt.org/directory # Production LE server
    privateKeySecretRef:
      # K8s Secret name to store the ACME account private key
      name: letsencrypt-prod-account-key
    # Define how to solve challenges (HTTP01 or DNS01)
    solvers:
    - http01: # Easiest for most setups with an Ingress controller
        ingress:
          # Use the Traefik ingress controller (if using standard Ingress)
          # class: traefik # Use this if Traefik is default IngressClass
          # OR configure specifically for Traefik IngressRoute (check Cert-Manager docs)
          # This might require specific service/pod setup for the solver
          # For Traefik CRDs, often DNS01 is easier if you can automate DNS updates
      # Example DNS01 solver (requires configuring DNS provider credentials)
      # - dns01:
      #     cloudflare: # Or route53, hetzner, etc.
      #       email: ${ACME_EMAIL_ADDRESS}
      #       apiTokenSecretRef:
      #         name: cloudflare-api-token-secret
      #         key: api-token
Test: kubectl get clusterissuer letsencrypt-prod. Check status/conditions.
[ ] 9.9: Deploy Harbor (Container Registry)

Context: Provides a private, self-hosted container registry with vulnerability scanning, RBAC, and other enterprise features. Requires persistent storage (via CSI) and ingress (via Traefik).
Implementation Detail: Create clusters/hetzner/registry/harbor.yaml:
YAML

# clusters/hetzner/registry/harbor.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: harbor # Source repo name
  namespace: flux-system
spec:
  interval: 1h
  url: https://helm.goharbor.io
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: harbor
  namespace: harbor # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: harbor
      version: "1.14.0" # Specify stable version compatible with your K8s
      sourceRef:
        kind: HelmRepository
        name: harbor
        namespace: flux-system
  values:
    expose:
      type: ingress # Use Traefik Ingress
      tls:
        enabled: false # TLS handled by Traefik/Cert-Manager at the edge
      ingress:
        # Use Traefik IngressRoute CRD instead of standard Ingress for better control
        # Set className: "traefik" if needed, or leave blank if Traefik default
        # controller: "traefik" # This might be needed depending on chart/Traefik setup
        hosts:
          core: harbor.${YOUR_DOMAIN} # Set your desired Harbor hostname
          # notary: harbor-notary.${YOUR_DOMAIN} # If using Notary
        # annotations: # Add Cert-Manager annotations if using standard Ingress
          # cert-manager.io/cluster-issuer: letsencrypt-prod
    # Use externalURL that matches ingress host
    externalURL: https://harbor.${YOUR_DOMAIN}
    # Configure persistence using Hetzner CSI StorageClass
    persistence:
      enabled: true
      resourcePolicy: "keep" # Keep PVs if HelmRelease deleted
      persistentVolumeClaim:
        registry: { storageClass: "hcloud-volumes", size: 50Gi } # Adjust size
        jobservice: { storageClass: "hcloud-volumes", size: 1Gi }
        database: { storageClass: "hcloud-volumes", size: 5Gi }
        redis: { storageClass: "hcloud-volumes", size: 1Gi }
        trivy: { storageClass: "hcloud-volumes", size: 5Gi }
    # Secrets Management:
    # Configure admin password, secret key, etc.
    # BEST PRACTICE: Use secrets synced from Infisical via K8s Secrets
    # Example referencing K8s secrets synced by Infisical Operator:
    harborAdminPasswordSecret: # Secret must exist in 'harbor' namespace
       name: harbor-admin-creds
       key: password
    secretKeySecret:
       name: harbor-internal-secrets
       key: secretKey
    database.passwordSecret:
       name: harbor-internal-secrets
       key: databasePassword
    redis.passwordSecret:
       name: harbor-internal-secrets
       key: redisPassword
    trivy.secretName: harbor-internal-secrets
    trivy.secretKey: trivyRedisPassword
    # ... other secret references ...

    # Enable Trivy vulnerability scanner
    trivy:
      enabled: true
      ignoreUnfixed: true

    # Disable components not needed? (e.g., Notary, Chartmuseum)
    chartmuseum: { enabled: false }
    notary: { enabled: false }
Create clusters/hetzner/apps/harbor-ingressroute.yaml (example):
YAML

# clusters/hetzner/apps/harbor-ingressroute.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: harbor-core
  namespace: harbor # Match Harbor's namespace
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`harbor.${YOUR_DOMAIN}`)
      kind: Rule
      services:
        # Point to the Harbor portal service created by the Helm chart
        - name: harbor-portal # Verify service name from Helm chart
          port: 80
      middlewares: # Optional: Add auth middleware later
        # - name: your-auth-middleware
        #   namespace: default
  tls:
    # Use Cert-Manager ClusterIssuer
    secretName: harbor-tls # Cert-Manager will create this secret
    # OR use Tailscale resolver if host is *.ts.net
    # certResolver: tailscaleresolver
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-tls # Name used in IngressRoute secretName
  namespace: harbor
spec:
  secretName: harbor-tls # Name of the K8s secret to store the cert
  issuerRef:
    name: letsencrypt-prod # Your ClusterIssuer
    kind: ClusterIssuer
  dnsNames:
    - harbor.${YOUR_DOMAIN} # Match host in IngressRoute
Test: kubectl get pods,pvc,svc,ingressroute -n harbor. Access https://harbor.${YOUR_DOMAIN}. Log in, push/pull image. Check PVCs bound.
[ ] 9.10: Deploy Infisical Operator

Context: Syncs secrets securely from your Infisical instance into Kubernetes Secret objects.
Implementation Detail: Create clusters/hetzner/secrets-sync/infisical-operator.yaml:
YAML

# clusters/hetzner/secrets-sync/infisical-operator.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: infisical-operator-system
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: infisical-helm-charts
  namespace: flux-system
spec:
  interval: 1h
  url: https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: infisical-operator
  namespace: infisical-operator-system # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: infisical-operator
      version: "0.3.1" # Check for latest stable version
      sourceRef:
        kind: HelmRepository
        name: infisical-helm-charts
        namespace: flux-system
  # Operator configuration (e.g., log level) goes here if needed
  # values:
  #   logLevel: info
  # Requires RBAC, which should be included in the chart
Create clusters/hetzner/secrets-sync/infisical-secrets.yaml (Example syncing Harbor admin pass):
YAML

# clusters/hetzner/secrets-sync/infisical-secrets.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: harbor-admin-creds # Name used by Harbor HelmRelease secret reference
  namespace: harbor # Sync into Harbor's namespace
spec:
  # Authentication method to connect to Infisical
  authentication:
    serviceToken: # Assumes using Service Token auth
      serviceTokenSecretReference: # K8s secret holding the Infisical service token
        secretName: infisical-bootstrap-token # Needs secure creation!
        secretNamespace: infisical-operator-system # Where bootstrap token lives
        # key: # Optional key within the secret, defaults to serviceToken
  # Managed Kubernetes secret configuration
  managedSecretReference:
    secretName: harbor-admin-creds # Name of the K8s secret to create/manage
    secretNamespace: harbor # Namespace for the K8s secret
  # Secrets to sync from Infisical
  secrets:
    # Key in K8s Secret : Path within Infisical project/environment
    password: /harbor/admin/password # Example path in Infisical
    # Add other key mappings as needed
Secure Bootstrap: The infisical-bootstrap-token K8s secret needs to be created securely before the InfisicalSecret CRD is applied. You could encrypt this secret using sops in your Flux repo or use another secure method.
Test: kubectl get pods -n infisical-operator-system. Verify InfisicalSecret CRD applied (kubectl get infisicalsecret -A). Check operator logs. Verify K8s secret harbor-admin-creds created in harbor namespace (kubectl get secret harbor-admin-creds -n harbor).
[ ] 9.11: Deploy Observability Stack

Context: Deploys components for collecting, storing, and visualizing logs, metrics, and traces (Otel Collector -> SigNoz, Grafana, Pixie). Assumes SigNoz backend is running elsewhere or deployed separately.
Implementation Detail:
OpenTelemetry Collector (observability/otel-collector.yaml):
YAML

# clusters/hetzner/observability/otel-collector.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring # Or reuse existing observability namespace
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: open-telemetry
  namespace: flux-system
spec:
  interval: 1h
  url: https://open-telemetry.github.io/opentelemetry-helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: opentelemetry-collector
  namespace: monitoring
spec:
  interval: 15m
  chart:
    spec:
      chart: opentelemetry-collector
      version: "0.80.0" # Check latest compatible version
      sourceRef:
        kind: HelmRepository
        name: open-telemetry
        namespace: flux-system
  values:
    mode: daemonset # Collect logs/metrics from each node
    config:
      # Define receivers, processors, exporters, service pipelines
      # See SigNoz / OpenTelemetry Collector docs for full config
      # Example Snippets:
      receivers:
        otlp: # For traces/metrics from apps/Traefik
          protocols: { grpc: {}, http: {} }
        # FluentForward for logs, or use filelog receiver
        # fluentforward: { endpoint: 0.0.0.0:24224 }
        filelog: # Collect container logs
          include: [ /var/log/pods/*/*/*.log ]
          start_at: beginning
          include_file_path: true
          include_file_name: false
          operators: # Parse k8s format
          - type: K8sLogParser # Custom parser might be needed
        # Host metrics receiver for node metrics
        hostmetrics:
          collection_interval: 30s
          scrapers: { cpu: {}, disk: {}, filesystem: {}, memory: {}, network: {}, load: {}, paging: {} }
      processors:
        # Enrich with K8s metadata
        k8sattributes: { passthrough: false }
        memory_limiter: { check_interval: 1s, limit_percentage: 75, spike_limit_percentage: 15 }
        batch: {}
      exporters:
        otlphttp: # Send everything to SigNoz backend
          endpoint: ${SIGNOZ_OTLP_ENDPOINT} # Use env var or secret
          # headers: # If auth needed for SigNoz
          #   "signoz-access-token": "${SIGNOZ_INGESTION_KEY}"
      service:
        pipelines:
          traces: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlphttp] }
          metrics: { receivers: [otlp, hostmetrics], processors: [memory_limiter, batch], exporters: [otlphttp] }
          logs: { receivers: [otlp, filelog], processors: [k8sattributes, memory_limiter, batch], exporters: [otlphttp] }
    # Mount necessary host paths for log/metric collection
    presets:
      logsCollection: { enabled: true } # Chart preset might handle mounts
      # metricsCollection: { enabled: true } # Chart preset
    # Tolerations if needed
    # Tolerations: [{"operator": "Exists"}]
Grafana (observability/grafana.yaml):
YAML

# clusters/hetzner/observability/grafana.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: grafana
  namespace: flux-system
spec:
  interval: 1h
  url: https://grafana.github.io/helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: grafana
  namespace: monitoring # Deploy in same namespace as collector
spec:
  interval: 15m
  chart:
    spec:
      chart: grafana
      version: "7.3.11" # Check latest stable version
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    # Configure admin password via K8s secret synced from Infisical
    admin:
      existingSecret: grafana-admin-creds # Secret name synced by Infisical
      userKey: username # Key in the secret
      passwordKey: password # Key in the secret
    persistence:
      enabled: true
      type: pvc
      storageClassName: "hcloud-volumes" # Use Hetzner CSI
      size: 10Gi
    # Configure Ingress via Traefik IngressRoute CRD separately
    ingress: { enabled: false }
    # Configure datasources
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: SigNoz-OTLP # Datasource for SigNoz
          type: otlp
          url: http://otel-collector-collector.monitoring:4318 # OTLP HTTP endpoint of collector service
          access: proxy
          jsonData: {}
        # Add Prometheus datasource if using it
        # - name: Prometheus
        #   type: prometheus
        #   url: http://prometheus-server.monitoring.svc.cluster.local
        #   access: proxy
        # Add Pixie datasource if using it
        # - name: Pixie
        #   type: pixie-datasource
        #   jsonData:
        #     clusterId: "<your-pixie-cluster-id>" # Requires Pixie deployment first
    # Optional: Import dashboards via sidecar/configmap
    # dashboardProviders: ...
    # dashboards: ...
Pixie (observability/pixie.yaml): (Optional)
YAML

# clusters/hetzner/observability/pixie.yaml
# Requires Pixie Cloud account OR self-hosted Pixie Cloud
# Follow Pixie Helm chart instructions: https://docs.px.dev/installing-pixie/install-schemes/helm/
# Example structure (details depend on Pixie chart version):
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: pixie-charts
  namespace: flux-system
spec:
  interval: 1h
  url: https://helm.px.dev
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: pixie-operator-vizier
  namespace: px-operator # Pixie often uses its own namespaces
spec:
  interval: 15m
  chart:
    spec:
      chart: pixie-operator-chart # Chart name might differ
      version: "0.x.y" # Check latest version
      sourceRef:
        kind: HelmRepository
        name: pixie-charts
        namespace: flux-system
  values:
    deployKey: ${PIXIE_DEPLOY_KEY} # Must be provided securely (Infisical/SOPS K8s Secret)
    clusterName: ${K3S_CLUSTER_NAME:-k3s-us-east}
    # devCloudNamespace: "" # Set if using self-hosted Pixie Cloud
Test: Check pods in monitoring (or other namespaces used) are running. Verify Grafana UI is accessible (configure IngressRoute). Check SigNoz UI for incoming data. Check Pixie UI (if deployed).
[ ] 9.12: Deploy Security Tools

Context: Installs Falco for runtime security detection and Kyverno for policy enforcement.
Implementation Detail:
Falco (security/falco.yaml):
YAML

# clusters/hetzner/security/falco.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: falco
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: falcosecurity
  namespace: flux-system
spec:
  interval: 1h
  url: https://falcosecurity.github.io/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: falco
  namespace: falco # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: falco
      version: "3.8.0" # Check latest stable version
      sourceRef:
        kind: HelmRepository
        name: falcosecurity
        namespace: flux-system
  values:
    # Use modern eBPF probe if kernel supports it (check Falco docs)
    driver:
      kind: ebpf
    # Enable JSON output for easier log consumption
    falco:
      jsonOutput: true
      logLevel: info
    # Optional: Enable falcosidekick for sending alerts (e.g., to Discord/Slack/SMTP)
    # falcosidekick:
    #   enabled: true
    #   config:
    #     discord:
    #       webhookurl: ${FALCO_DISCORD_WEBHOOK} # Provide securely
Kyverno (security/kyverno.yaml):
YAML

# clusters/hetzner/security/kyverno.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kyverno
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: kyverno
  namespace: flux-system
spec:
  interval: 1h
  url: https://kyverno.github.io/kyverno/
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: kyverno
  namespace: kyverno # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: kyverno
      version: "3.2.3" # Check latest stable version
      sourceRef:
        kind: HelmRepository
        name: kyverno
        namespace: flux-system
  values:
    # Install CRDs needed by Kyverno policies
    installCRDs: true
    # Configure admission controller settings
    admissionController:
      replicas: 1 # Start with 1, increase if needed
      # Default failure policy is Ignore, change to Fail if needed
      # failurePolicy: Fail
    # Background controller for generate policies, cleanup etc.
    backgroundController: { replicas: 1 }
    # Reporting controller for PolicyReports
    reportController: { replicas: 1 }
Kyverno Policies (security/policies/): Create ClusterPolicy YAML files in a subdirectory (e.g., security/policies/) and include them via the security/kustomization.yaml file. Start with policies in validationFailureAction: Audit.
Test: kubectl get pods -n falco, kubectl get pods -n kyverno. Check Falco logs for rule loading. Apply a test policy and verify kubectl get clusterpolicy.
[ ] 9.13: Deploy Delivery Tools

Context: Installs Flagger for automating progressive delivery strategies like canary releases.
Implementation Detail: Create clusters/hetzner/delivery/flagger.yaml:
YAML

# clusters/hetzner/delivery/flagger.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: flagger-system
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: flagger
  namespace: flux-system
spec:
  interval: 1h
  # Flagger is part of FluxCD project now, use their chart repo
  url: https://fluxcd-community.github.io/helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: flagger
  namespace: flagger-system # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: flagger
      version: "1.34.1" # Check latest stable version
      sourceRef:
        kind: HelmRepository
        name: flagger # Use correct repo name
        namespace: flux-system
  values:
    # Configure for Traefik provider
    provider: traefik
    # Enable Prometheus integration if using Prometheus for metrics
    # metricsServer: http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090
    # Or configure webhook integration if using SigNoz metrics/analysis
    # See Flagger documentation for webhook configuration
    # Optional: Configure Slack/Discord notifications
    # slack:
    #   url: ${FLAGGER_SLACK_WEBHOOK}
    #   channel: "#k8s-deployments"
    #   user: "flagger"
Test: kubectl get pods -n flagger-system.
[ ] 9.14: Deploy Backup Tools

Context: Installs Velero for Kubernetes backups, configured to use MinIO running on your Synology NAS as the storage backend.
Implementation Detail:
Setup MinIO on Synology NAS: (Manual Step) Follow Phase 1 guide: Install Container Manager, run MinIO container mapping a NAS volume to /data, expose ports 9000/9001, set access/secret keys, create velero-backups bucket. Note the Synology's IP, MinIO access key, and secret key.
Create MinIO Secret (backup/minio-secret.yaml): Create a K8s secret containing the MinIO credentials. Manage this via Infisical sync or encrypt with SOPS in the Flux repo.
YAML

# Example (manage via Infisical/SOPS instead of plaintext commit!)
# apiVersion: v1
# kind: Secret
# metadata:
#   name: velero-minio-creds
#   namespace: velero # Namespace where Velero is installed
# stringData:
#   cloud: |
#     [default]
#     aws_access_key_id = ${MINIO_ACCESS_KEY}
#     aws_secret_access_key = ${MINIO_SECRET_KEY}
Deploy Velero (backup/velero.yaml):
YAML

# clusters/hetzner/backup/velero.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: velero
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: vmware-tanzu # Velero chart repo
  namespace: flux-system
spec:
  interval: 1h
  url: https://vmware-tanzu.github.io/helm-charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: velero
  namespace: velero # Deploy into its own namespace
spec:
  interval: 15m
  chart:
    spec:
      chart: velero
      version: "5.1.3" # Check latest stable version
      sourceRef:
        kind: HelmRepository
        name: vmware-tanzu
        namespace: flux-system
  values:
    # Install CRDs needed by Velero
    crds: { enabled: true }
    # Configure BackupStorageLocation for MinIO
    configuration:
      provider: aws # Use AWS provider for S3 compatible
      backupStorageLocation:
        - name: default
          provider: aws
          bucket: velero-backups # Your MinIO bucket name
          config:
            region: us-east-1 # Required dummy region for MinIO
            s3ForcePathStyle: "true"
            s3Url: http://${MINIO_SYNOLOGY_IP}:9000 # Your MinIO endpoint
            # Optional: insecureSkipTLSVerify: "true" if using self-signed certs
          credential:
            name: velero-minio-creds # K8s secret with MinIO keys
            key: cloud
      # Configure VolumeSnapshotLocation (if using CSI)
      # volumeSnapshotLocation:
      #   - name: hetzner-csi
      #     provider: hetzner.csi.hetzner.com
    # Enable Restic DaemonSet for PV data backup if not using CSI snapshots
    deployRestic: true
    # Reference the K8s secret with credentials
    credentials:
      useSecret: true
      existingSecret: velero-minio-creds # Must match secret name
      # secretContents: # Use this only if not using existingSecret
      #   cloud: |
      #     [default]
      #     aws_access_key_id=...
      #     aws_secret_access_key=...

    # Resource requests/limits for Velero pods
    resources:
      requests: { cpu: 100m, memory: 128Mi }
      limits: { cpu: 500m, memory: 512Mi }
    # Restic specific resources
    restic:
      resources:
        requests: { cpu: 500m, memory: 512Mi }
        limits: { cpu: "1", memory: "1Gi" }
Create Schedules (backup/schedules.yaml): Define Velero Schedule CRDs in Flux to automate backups (e.g., daily).
Test: kubectl get pods -n velero. Run velero backup create test-backup --wait. Check MinIO bucket for backup files. Test restore later (Phase 12).
Phase 10: Traefik-Tailscale Integration
[ ] 10.1: Review Existing Traefik-Tailscale Configuration

Context: Verify the configuration intended for Traefik to automatically obtain TLS certificates for services exposed on your .ts.net domain.
Implementation Detail: Check additionalArguments in apps/traefik.yaml includes --certificatesresolvers.tailscaleresolver.tailscale={}. Review files in /home/evan/2_Dev/2.1_Homelab/!kube-flux/traefik-tailscale if they contain relevant CRDs like Middleware or TLSOptions intended for Tailscale use.
[ ] 10.2: Deploy Traefik with Tailscale Support

Context: Ensure the Traefik HelmRelease (defined in 9.6) includes the necessary arguments for the Tailscale resolver.
Implementation Detail: (Covered by verification in 10.1). Flux applies the HelmRelease.
Test: kubectl get pods -n traefik-system. Check Traefik logs for successful startup and registration of the tailscaleresolver.
[ ] 10.3: Apply Secure Headers Middleware

Context: Deploys a standard Middleware CRD to add security headers (like STS, NoSniff, XSS protection) to responses. This should be applied to most public-facing or internal routes.
Implementation Detail: Create clusters/hetzner/apps/traefik-middleware-secure-headers.yaml (or similar name):
YAML

# clusters/hetzner/apps/traefik-middleware-secure-headers.yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  # Use a common namespace or Traefik's namespace
  name: default-secure-headers
  namespace: default # Or traefik-system
spec:
  headers:
    browserXssFilter: true
    contentTypeNosniff: true
    forceSTSHeader: true
    stsIncludeSubdomains: true
    stsPreload: true
    stsSeconds: 31536000 # One year
    customFrameOptionsValue: "SAMEORIGIN"
    # Add other headers like Content-Security-Policy as needed
Include this manifest in the apps/kustomization.yaml. Commit and push to Flux repo.
Test: kubectl get middleware default-secure-headers -n default (or relevant namespace).
[ ] 10.4: Create Sample IngressRoute (Tailscale)

Context: Defines routing for a sample application, specifically using the tailscaleresolver to get a TLS certificate for its .ts.net hostname. Also applies the secure headers middleware.
Implementation Detail: Create clusters/hetzner/apps/sample-app-route.yaml:
Bash

# Example using kubectl apply for quick test - move to Flux later!
# 1. Deploy sample app
kubectl create deployment sample-app --image=nginxdemos/hello --port=80 --namespace=default
kubectl expose deployment sample-app --port=80 --namespace=default

# 2. Create IngressRoute manifest
cat > "/tmp/sample-ingressroute.yaml" << EOF
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: sample-app-tailscale
  namespace: default
spec:
  entryPoints:
    - websecure # Use the HTTPS entrypoint
  routes:
    # Match the Tailscale magic DNS name
    - match: Host(\`sample-app.${TAILSCALE_DOMAIN:-cinnamon-galaxy.ts.net}\`) # Use env var
      kind: Rule
      middlewares:
        # Apply secure headers (ensure namespace matches where middleware deployed)
        - name: default-secure-headers
          namespace: default # Or traefik-system
      services:
        - name: sample-app # K8s Service name
          port: 80 # K8s Service port
  tls:
    # Tell Traefik to use Tailscale to get a cert for the Host defined above
    certResolver: tailscaleresolver
EOF

# 3. Apply the manifest
kubectl apply -f /tmp/sample-ingressroute.yaml
Test: kubectl get ingressroute sample-app-tailscale -n default. Check status and associated services/middleware.
[ ] 10.5: Test Tailscale Access

Context: Verify end-to-end functionality: Traefik routing, Tailscale TLS certificate issuance, middleware application, and connection to the backend service.
Implementation Detail: From a machine logged into your Tailnet:
Bash

# Use -k if needed initially while cert propagates, remove later
curl -v https://sample-app.${TAILSCALE_DOMAIN:-cinnamon-galaxy.ts.net}
# Check output for 'Server: nginx' and response headers for security headers
# Check certificate details using browser or openssl s_client
Test: Successful HTTPS connection (HTTP 200), valid TLS certificate issued for the .ts.net name, presence of security headers in response.
Phase 11: Attic Deployment (Optional Nix Cache)
Context: Attic provides a self-hosted Nix binary cache, reducing build times by storing and serving previously built Nix store paths. It uses MinIO (on Synology) for storage and requires secrets managed via Infisical.

[ ] 11.1: Verify Prerequisites

Context: Ensure MinIO (on Synology) and the Infisical Operator (for secrets) are running and accessible from within the cluster.
Implementation Detail:
Bash

# Check MinIO access (e.g., using mc client or checking Velero backup status)
echo "Verify MinIO endpoint http://${MINIO_SYNOLOGY_IP}:9000 is accessible"
# Check Infisical Operator
kubectl get pods -n infisical-operator-system
Test: MinIO endpoint reachable, Infisical operator pods are running.
[ ] 11.2: Prepare Attic Secrets (via Infisical)

Context: Securely store Attic's required secrets (token signing secret, cache signing keys from $ATTIC_CACHE_KEY, MinIO S3 credentials) in your Infisical instance. Define an InfisicalSecret CRD to sync these into a K8s Secret (e.g., attic-secrets in the attic namespace).
Implementation Detail:
Add Secrets to Infisical: Use Infisical UI/CLI to add secrets like ATTIC_TOKEN_SIGNING_SECRET, ATTIC_CACHE_SIGNING_KEYS, MINIO_ACCESS_KEY, MINIO_SECRET_KEY under a suitable path (e.g., /k8s/attic). Generate a strong random value for ATTIC_TOKEN_SIGNING_SECRET.
Create InfisicalSecret CRD (secrets-sync/attic-secrets.yaml):
YAML

# clusters/hetzner/secrets-sync/attic-secrets.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${ATTIC_NAMESPACE:-attic}
---
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: attic-secrets # K8s secret name referenced by Attic HelmRelease
  namespace: ${ATTIC_NAMESPACE:-attic} # Target namespace for K8s secret
spec:
  authentication:
    serviceToken: # Assumes using Service Token auth for Operator
      serviceTokenSecretReference:
        secretName: infisical-bootstrap-token # Your operator's auth token secret
        secretNamespace: infisical-operator-system
  managedSecretReference:
    secretName: attic-secrets # K8s secret to create/manage
    secretNamespace: ${ATTIC_NAMESPACE:-attic}
  secrets: # Mapping from K8s Secret Key : Infisical Secret Path
    ATTIC_SERVER_TOKEN_SIGNING_SECRET: /k8s/attic/token-signing-secret
    ATTIC_SERVER_CACHE_SIGNING_KEYS: /k8s/attic/cache-signing-keys # Store $ATTIC_CACHE_KEY here
    ATTIC_SERVER_S3_ACCESS_KEY: /k8s/minio/access-key # Use existing MinIO creds if same
    ATTIC_SERVER_S3_SECRET_KEY: /k8s/minio/secret-key
Commit this file to your Flux repo (secrets-sync/kustomization.yaml should reference it).
Test: After Flux syncs, verify the K8s secret exists: kubectl get secret attic-secrets -n ${ATTIC_NAMESPACE:-attic}.
[ ] 11.3: Deploy Attic

Context: Deploys Attic server using its Helm chart, configuring it to use the secrets synced by Infisical and the MinIO backend on Synology. Exposes via Traefik/Tailscale.
Implementation Detail: Create clusters/hetzner/registry/attic.yaml (or apps/attic.yaml):
YAML

# clusters/hetzner/registry/attic.yaml (or apps/)
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: attic # Source Repo name
  namespace: flux-system
spec:
  interval: 1h
  url: https://zhaofengli.github.io/attic # Official Attic chart repo
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: attic
  namespace: ${ATTIC_NAMESPACE:-attic} # Use namespace defined in 11.2
spec:
  interval: 15m
  chart:
    spec:
      chart: attic
      version: "0.7.1" # Check for latest stable version
      sourceRef:
        kind: HelmRepository
        name: attic
        namespace: flux-system
  values:
    server:
      host: "0.0.0.0" # Listen on all interfaces within pod
      port: 8080
      dataDirectory: "/data" # Needs persistent volume if not using S3 effectively
      # Reference secrets from the K8s secret synced by Infisical
      tokenSigningSecret:
        name: attic-secrets # K8s secret name
        key: ATTIC_SERVER_TOKEN_SIGNING_SECRET # Key within the secret
      cacheSigningKeys:
        name: attic-secrets
        key: ATTIC_SERVER_CACHE_SIGNING_KEYS
      s3:
        endpoint: "http://${MINIO_SYNOLOGY_IP}:9000" # Endpoint for MinIO on NAS
        region: "us-east-1" # Dummy region
        bucket: "attic" # Ensure this bucket exists in MinIO
        accessKey:
          name: attic-secrets
          key: ATTIC_SERVER_S3_ACCESS_KEY
        secretKey:
          name: attic-secrets
          key: ATTIC_SERVER_S3_SECRET_KEY
        # Use path style access for MinIO
        usePathStyle: true

    # Define ingress using Traefik IngressRoute CRD separately for more control
    ingress:
      enabled: false # Disable chart's default ingress
    # Define persistence if needed (e.g., for logs, though S3 is primary)
    # persistence:
    #   enabled: true
    #   storageClass: hcloud-volumes
    #   size: 10Gi

    # Resources requests/limits
    resources:
      requests: { cpu: 200m, memory: 256Mi }
      limits: { cpu: "1", memory: "1Gi" }
---
# Define Traefik IngressRoute separately (e.g., in apps/attic-route.yaml)
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: attic-ingress
  namespace: ${ATTIC_NAMESPACE:-attic}
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`attic.${TAILSCALE_DOMAIN:-cinnamon-galaxy.ts.net}`) # Use Tailscale domain
      kind: Rule
      services:
        - name: attic # Service name created by Helm chart
          port: 8080 # Service port exposed by chart
      middlewares:
        # Add secure headers, potentially auth middleware later
        - name: default-secure-headers
          namespace: default # Or traefik-system
  tls:
    certResolver: tailscaleresolver # Use Tailscale for TLS
Test: kubectl get pods,svc,ingressroute -n ${ATTIC_NAMESPACE:-attic}. Check logs. Access https://attic.${TAILSCALE_DOMAIN}.
[ ] 11.4: Configure Attic

Context: Ensure Attic server starts correctly and connects to the MinIO backend using the provided credentials.
Implementation Detail: Check Attic pod logs for successful startup and S3 connection messages. Use attic status command:
Bash

# Get pod name
ATTIC_POD=$(kubectl get pods -n ${ATTIC_NAMESPACE:-attic} -l app.kubernetes.io/name=attic -o jsonpath='{.items[0].metadata.name}')
# Check status (may require specific command if status isn't exposed)
kubectl logs -n ${ATTIC_NAMESPACE:-attic} $ATTIC_POD
# Attempt to interact via CLI if installed locally and configured for the server
Test: Pod running, logs show successful S3 connection. attic login <cache-url> works.
[ ] 11.5: Test Attic Binary Cache

Context: Verify end-to-end functionality by creating a cache, pushing a Nix build artifact, signing it, and pulling it from another machine configured to use the cache. Requires Attic client setup and cache key ($ATTIC_CACHE_KEY from Infisical).
Implementation Detail:
Bash

# Run commands from a machine with nix and attic client configured
# 1. Login to your Attic server (replace URL)
attic login k8s-cache https://attic.${TAILSCALE_DOMAIN}
# Provide login token if required by server config

# 2. Create a test cache on the server
attic cache create k8s-cache testcache

# 3. Get your cache signing key (stored in Infisical, synced to K8s secret, need local copy)
# Example: kubectl get secret attic-secrets -n ${ATTIC_NAMESPACE:-attic} -o jsonpath='{.data.ATTIC_SERVER_CACHE_SIGNING_KEYS}' | base64 -d > ~/.config/attic/keys/testcache.sk
# Ensure ~/.config/attic/keys/testcache.sk contains the SECRET key part

# 4. Build a simple package
nix-build '<nixpkgs>' -A hello

# 5. Sign the build output (replace path if needed)
attic sign k8s-cache testcache -k testcache ./result

# 6. Push the signed paths to the cache
attic push k8s-cache testcache ./result

# 7. On another machine (or after cleaning local store): Configure nix.conf
# sudo nano /etc/nix/nix.conf
# Add:
# substituters = https://attic.${TAILSCALE_DOMAIN}/testcache https://cache.nixos.org/
# trusted-public-keys = testcache:<PUBLIC_KEY_PART_OF_ATTIC_CACHE_KEY> cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
# sudo systemctl restart nix-daemon.service

# 8. Try to realize the path (should pull from Attic)
nix-store -r $(nix-store -qR ./result) # Use the specific output path
# Check nix log output for cache hits
Test: Package is pushed successfully. attic pull or nix build on another machine successfully downloads from the cache.
Phase 12: Validation and Testing
Context: Thoroughly test all deployed components to ensure the cluster is fully operational and configured as expected.

[ ] 12.1: Verify All Nodes
Implementation: kubectl get nodes -o wide
Test: All expected nodes (control, static workers) are listed and in Ready state with correct roles and IPs.
[ ] 12.2: Verify All System Pods
Implementation: kubectl get pods -A
Test: All pods in kube-system, flux-system, traefik-system, cert-manager, harbor, infisical-operator-system, monitoring, security, delivery, backup, attic namespaces are Running or Completed. Troubleshoot any CrashLoopBackOff or Error states.
[ ] 12.3: Test Storage Provisioning (Hetzner CSI)
Implementation: Create a test PVC and a pod mounting it:
Bash

# Create PVC (if deleted from previous step)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: test-pvc, namespace: default}
spec: {accessModes: [ReadWriteOnce], storageClassName: hcloud-volumes, resources: {requests: {storage: 1Gi}}}
EOF
# Create Pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: {name: storage-test-pod, namespace: default}
spec:
  containers:
  - name: busybox
    image: busybox:latest
    command: ["sleep", "3600"]
    volumeMounts: [{name: test-vol, mountPath: /data}]
  volumes: [{name: test-vol, persistentVolumeClaim: {claimName: test-pvc}}]
EOF
Test: kubectl get pvc test-pvc shows Bound. kubectl get pod storage-test-pod shows Running. hcloud volume list shows the corresponding volume created in Hetzner Cloud. kubectl exec storage-test-pod -- touch /data/hello works. Clean up: kubectl delete pod storage-test-pod, kubectl delete pvc test-pvc.
[ ] 12.4: Test Load Balancer Provisioning (Hetzner CCM)
Implementation: Create test deployment and Service type LoadBalancer:
Bash

kubectl create deployment test-lb --image=nginxdemos/hello --port=80 --namespace=default
kubectl expose deployment test-lb --port=80 --type=LoadBalancer --namespace=default --annotations="load-balancer.hetzner.cloud/location=${HETZNER_LOCATION:-ash},load-balancer.hetzner.cloud/use-private-ip=true"
Test: kubectl get svc test-lb -n default eventually shows a private IP under EXTERNAL-IP. hcloud load-balancer list shows the LB created in Hetzner. Test access from another node in the private network: curl <LB_PRIVATE_IP>. Clean up: kubectl delete svc test-lb, kubectl delete deployment test-lb.
[ ] 12.5: Test Cluster Autoscaler
Context: Requires a node pool labeled correctly (e.g., k8s-nodepool=autoscaled-workers) and CA configured to manage it (extraArgs.nodes or auto-discovery).
Implementation:
(If needed) Provision an initial node for the autoscaled pool: cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs && just create-worker-node 1 pool="autoscaled-workers" type="cpx21" (Ensure CA is configured for this pool/labels/type).
Deploy workload requesting significant resources targeting that nodepool's label:
Bash

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: autoscale-tester, namespace: default}
spec:
  replicas: 1 # Start small
  selector: {matchLabels: {app: autoscale-tester}}
  template:
    metadata: {labels: {app: autoscale-tester}}
    spec:
      nodeSelector: { k8s-nodepool: autoscaled-workers } # Target the pool
      containers: [{name: stress, image: polinux/stress, args: ["--cpu", "1", "--vm", "1", "--vm-bytes", "750M"], resources: {requests: {cpu: "900m", memory: "800Mi"}}}] # Request large resources
EOF
Scale replicas to force node creation: kubectl scale deployment autoscale-tester --replicas=5 (adjust based on node size/pool limits).
Test: Monitor kubectl get nodes -l k8s-nodepool=autoscaled-workers. New nodes should be provisioned by Hetzner and join the cluster. Check CA logs: kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler -f. Scale down kubectl scale deployment autoscale-tester --replicas=0 and verify nodes are eventually removed by CA after scale-down delays. Clean up: kubectl delete deployment autoscale-tester.
[ ] 12.6: Test Ingress and TLS (Traefik + Cert-Manager)
Context: Verify Traefik routes external traffic and Cert-Manager provides valid Let's Encrypt certificates. Requires DNS pointing your test domain to Traefik's LoadBalancer public IP (or equivalent CNAME).
Implementation: Create test deployment/service and an IngressRoute using the letsencrypt-prod ClusterIssuer:
Bash

# Deploy test app (if sample-app deleted)
kubectl create deployment test-tls --image=nginxdemos/hello --port=80 -n default
kubectl expose deployment test-tls --port=80 -n default

# Create IngressRoute and Certificate request via Flux manifest
# clusters/hetzner/apps/test-tls-route.yaml
cat > "/home/evan/2_Dev/2.1_Homelab/!kube-flux/clusters/hetzner/apps/test-tls-route.yaml" << EOF
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: test-tls-route
  namespace: default
spec:
  entryPoints: ["websecure"]
  routes:
  - match: Host(\`test-tls.${YOUR_DOMAIN}\`) # Use your real domain
    kind: Rule
    services: [{ name: test-tls, port: 80 }]
    middlewares: [{ name: default-secure-headers, namespace: default }] # Use secure headers
  tls:
    secretName: test-tls-prod-secret # Cert-Manager creates this
    # Optional: Specify ClusterIssuer explicitly if needed
    # certResolver: letsencrypt-prod (usually not needed if secretName specified)
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-tls-prod-cert
  namespace: default
spec:
  secretName: test-tls-prod-secret # Must match IngressRoute tls.secretName
  issuerRef:
    name: letsencrypt-prod # Your ClusterIssuer
    kind: ClusterIssuer
  dnsNames:
  - test-tls.${YOUR_DOMAIN} # Your real domain
EOF
# Add test-tls-route.yaml to apps/kustomization.yaml, commit, push
Test: Wait for Flux sync. kubectl get certificate -n default test-tls-prod-cert should show Ready: True. kubectl get secret -n default test-tls-prod-secret should exist. Access https://test-tls.${YOUR_DOMAIN} in a browser, verify valid LE certificate and content. Clean up: Remove manifests from Flux repo.
[ ] 12.7: Test System Upgrade (SUC)
Context: Verify the System Upgrade Controller can perform a planned k3s upgrade. Use with caution, potentially disruptive. Test with a minor patch version first.
Implementation: Create Plan CRDs via Flux (infrastructure/k3s-upgrade-plan.yaml):
YAML

# clusters/hetzner/infrastructure/k3s-upgrade-plan.yaml
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-server-upgrade # Example name
  namespace: system-upgrade
spec:
  concurrency: 1 # Upgrade one master at a time
  # Use current K3S version + 1 patch level (e.g., from v1.28.5+k3s1 to v1.28.6+k3s1)
  version: ${TARGET_K3S_VERSION} # Set target version via env var or directly
  serviceAccountName: system-upgrade
  cordon: true
  # drain: # Optional fine-grained drain options
  #   force: true
  #   skipWaitForDeleteTimeout: 60
  nodeSelector:
    matchExpressions:
      - {key: node-role.kubernetes.io/control-plane, operator: Exists}
  upgrade:
    image: rancher/k3s-upgrade # Use official upgrade image
---
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: k3s-agent-upgrade
  namespace: system-upgrade
spec:
  concurrency: 2 # Upgrade workers in parallel
  version: ${TARGET_K3S_VERSION}
  serviceAccountName: system-upgrade
  cordon: true
  prepare: # Wait for server plan to complete before starting agents
    name: k3s-server-upgrade
    image: rancher/k3s-upgrade
    args: ["prepare", "k3s-server-upgrade"]
  nodeSelector:
    matchExpressions:
      - {key: node-role.kubernetes.io/control-plane, operator: DoesNotExist}
  upgrade:
    image: rancher/k3s-upgrade
Commit to Flux repo.
Test: Monitor kubectl get plans -n system-upgrade. Watch node statuses (kubectl get nodes). Verify node K3s versions (kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}') update after upgrade completes. Remove Plan manifests from Flux repo after successful upgrade.
[ ] 12.8: Test Traefik-Tailscale Integration
Context: Verify routing and automatic TLS for services exposed only on the Tailscale network.
Implementation: (Covered in Phase 10 test steps). Create IngressRoute using tailscaleresolver, test access via .ts.net hostname.
Test: Successful HTTPS connection to Tailscale service with valid cert.
[ ] 12.9: Test Harbor Registry
Context: Ensure the self-hosted Harbor registry is functional for pushing, pulling, and scanning images.
Implementation:
Log in to Harbor UI (https://harbor.${YOUR_DOMAIN}). Create a project (e.g., test-project).
Log in locally: docker login harbor.${YOUR_DOMAIN} (use admin credentials or create a user).
Tag an existing image or build a simple test image: docker pull hello-world && docker tag hello-world harbor.${YOUR_DOMAIN}/test-project/hello:v1.
Push the image: docker push harbor.${YOUR_DOMAIN}/test-project/hello:v1.
Verify image appears in Harbor UI, check vulnerability scan results (Trivy).
Pull the image: docker pull harbor.${YOUR_DOMAIN}/test-project/hello:v1.
Test: Login, push, pull successful. Image visible in UI with scan results.
[ ] 12.10: Test Infisical Secret Sync
Context: Verify the Infisical Operator correctly syncs secrets from Infisical to K8s Secret objects.
Implementation:
Create a test secret (e.g., MY_TEST_SECRET=hello_infisical) in Infisical under a path referenced by an InfisicalSecret CRD managed by Flux (e.g., sync /test/secret to K8s secret test-infisical-secret in default namespace).
Deploy a simple pod mounting this secret:
YAML

# Example test pod manifest (manage via Flux or kubectl apply)
apiVersion: v1
kind: Pod
metadata: {name: infisical-test-pod, namespace: default}
spec:
  containers:
  - name: test
    image: busybox:latest
    command: ["/bin/sh", "-c", "while true; do echo 'Secret:' $(cat /etc/secret-volume/MY_TEST_SECRET); sleep 30; done"]
    volumeMounts: [{name: secret-vol, mountPath: /etc/secret-volume}]
  volumes: [{name: secret-vol, secret: {secretName: test-infisical-secret}}] # Mounts K8s secret synced by operator
Test: Verify K8s secret test-infisical-secret exists and contains the correct key (MY_TEST_SECRET). Check pod logs: kubectl logs infisical-test-pod should show Secret: hello_infisical. Update the secret in Infisical UI/API and verify the pod logs eventually reflect the change (after operator sync interval). Clean up test pod/secret/CRD.
[ ] 12.11: Test Observability Stack
Context: Verify logs, metrics, and traces flow correctly to SigNoz and are viewable in Grafana. Test Pixie if deployed. Set up basic alerting.
Implementation:
Logs: Check SigNoz UI for logs from system components (kubelet, containerd via journald/filelog collector) and application pods (stdout). Verify Kubernetes metadata enrichment.
Metrics: Check SigNoz UI/Grafana for metrics (node-exporter/hostmetrics, kube-state-metrics if collected, app metrics, Traefik metrics).
Traces: Deploy a sample app instrumented with OpenTelemetry SDK (pointing to Otel Collector OTLP endpoint). Generate traffic. Check SigNoz UI for traces. Check Traefik traces.
Pixie: Access Pixie UI. Verify cluster auto-instrumentation, view service maps, inspect requests.
Alerting:
Configure receivers in Alertmanager (if using Prometheus) or SigNoz for Discord webhook and Email (SMTP).
Define test alert rules (e.g., up == 0 for a test job, high error log count in SigNoz).
Trigger the alert condition.
Test: Data visible in SigNoz/Grafana/Pixie. Test alert fires and notification is received via Discord/Email.
[ ] 12.12: Test Security Tools
Context: Verify Falco detects runtime threats and Kyverno enforces policies.
Implementation:
Falco: Check Falco pod logs (kubectl logs -n falco -l app.kubernetes.io/name=falco -f) for rule loading. Trigger a default rule (e.g., kubectl exec -it <some-pod> -- bash -c "touch /etc/foo"). Check logs or configured outputs (falcosidekick -> Discord) for the alert.
Kyverno: Create a resource that violates a policy set to Audit mode (e.g., deployment without required labels). Check Policy Reports: kubectl get policyreports -A -o yaml. Create a resource that violates a policy set to Enforce mode. Verify the resource creation is blocked by Kyverno's admission controller. Check Kyverno pod logs.
Test: Falco detects suspicious activity. Kyverno reports/blocks non-compliant resources as expected.
[ ] 12.13: Test Progressive Delivery (Flagger)
Context: Verify Flagger can manage a canary deployment orchestrated via Flux and Traefik.
Implementation:
Deploy a test application (e.g., podinfo) managed by Flux.
Create a Flagger Canary resource targeting the deployment, referencing Traefik, and defining analysis metrics/thresholds/steps. Commit via Flux.
Update the application's container image tag in its Flux manifest. Commit via Flux.
Test: Observe Flagger creating canary deployment/services. Monitor kubectl get canary -A and Flagger logs (kubectl logs -n flagger-system -l app=flagger -f). Verify traffic shifting (via Traefik dashboard/metrics or test traffic) and successful promotion or rollback based on analysis.
[ ] 12.14: Test Backups (Velero)
Context: Ensure Velero can successfully back up cluster state and PV data to MinIO on Synology and restore it.
Implementation:
Backup: velero backup create full-cluster-$(date +%Y%m%d%H%M%S) --wait (or use scheduled backup). Verify completion: velero backup get. Check backup files exist in the MinIO bucket on Synology.
Simulate Disaster: Delete a test deployment and its PVC: kubectl delete deployment test-pvc-app, kubectl delete pvc test-pvc. Verify resources are gone.
Restore: velero restore create --from-backup <backup-name> --wait.
Test: velero restore get. Verify deployment and PVC are recreated and data within the PV (if any) is restored correctly. Test frequently!
[ ] 12.15: Document Cluster Access & Usage
Context: Essential documentation for yourself and any other users.
Implementation Detail: Create/update README.md files in NixOS and/or Flux repos:
How to get/use kubeconfig.
How to access via Tailscale (MagicDNS names).
How to deploy apps (via Flux Git workflow).
Links to Grafana, SigNoz, Harbor, Traefik Dashboard UIs.
Basic troubleshooting links or runbook references.
Backup/restore procedure summary.
Test: Documentation is clear, accurate, and accessible.
[ ] 12.16: Set Up Monitoring and Alerting (Configuration)
Context: Define specific alerts based on application/cluster needs and configure notification routing.
Implementation Detail:
Define Alertmanager configuration (if using Prometheus) or SigNoz alert rules. Focus on actionable alerts (high latency/errors, resource saturation, component failures, certificate expiry via kube-prometheus-stack or cert-manager metrics).
Configure receivers for Discord (webhook) and Email (SMTP settings) in Alertmanager/SigNoz.
Create Grafana dashboards for key metrics and application health.
Test: Test alerts fire correctly and notifications are received. Dashboards display meaningful data.
(Phases 13, 14, 15 covering Maximizing Tools, Operations, and Future Steps would follow here, based on the detailed outlines provided in the previous response.)

Completion Checklist
(Use the checklist provided in your plan - ensure all deployed components are validated)

Code Reuse and Hardware Information
(Refer to the details provided in your plan - ensure NixOS configs leverage existing hardware data)[ ] 4.1: Set Up Sops Configuration

[ ] Create ./k3s-cluster/.sops.yaml with age public key from flake's devShell shellHook
Test: Verify file syntax with YAML validator
Context: Configures sops for encrypting secrets specifically within the ./k3s-cluster/secrets/ directory. It uses the age public key defined in your $ADMIN_AGE_PUBLIC_KEY environment variable.
Implementation Detail: Create the file ./k3s-cluster/.sops.yaml:
YAML

# /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/k3s-cluster/.sops.yaml
keys:
  # References the Age public key exported via direnv from flake's devShell shellHook
  - &admin ${ADMIN_AGE_PUBLIC_KEY:-age1p5vdpde60kwfjqeyufvp8xxtfk4ja39h42v4y26u8ju85ysw9y4qvuh0cd}
creation_rules:
  # This rule ensures only files matching this path regex get encrypted with the key above
  - path_regex: secrets/secrets\.yaml$
    key_groups:
      - age:
        - *admin # Uses the key defined above with the 'admin' anchor
[ ] 4.2: Create Secrets File

[ ] Create ./k3s-cluster/secrets/secrets.yaml with placeholders
Test: Verify file syntax with YAML validator
Context: This YAML file will store the NixOS bootstrap secrets (key-value pairs) encrypted by sops. It should only contain secrets needed by NixOS modules during build/activation.
Implementation Detail: Create the file ./k3s-cluster/secrets/secrets.yaml with initial structure:
YAML

# /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/k3s-cluster/secrets/secrets.yaml
# Secrets needed ONLY during NixOS build/bootstrap phase
k3s_token: ENC[...] # Populated & Encrypted in step 4.3
tailscale_authkey: ENC[...] # Populated & Encrypted in step 4.4
# --- DO NOT ADD K8s SECRETS (like HETZNER_API_TOKEN) HERE ---
# --- Manage those via Infisical or SOPS+Flux in the Flux repo ---
sops:
  # SOPS metadata will be automatically generated/updated upon encryption.
  lastmodified: '...'
  mac: '...'
  version: '...'
  encrypted_regex: ^(data|stringData)$ # Default SOPS encryption pattern
  age: [] # Will be populated with recipient details on first encryption
[ ] 4.3: Encrypt K3s Token

[ ] Add K3s token to secrets file
[ ] Encrypt with sops: sops --encrypt --in-place ./k3s-cluster/secrets/secrets.yaml
Test: Verify encryption with sops -d ./k3s-cluster/secrets/secrets.yaml | grep k3s_token. Commit the encrypted file to Git.
Context: Encrypts the $K3S_TOKEN for use by sops-nix to configure the services.k3s.tokenFile on control plane and worker nodes. Requires your age private key (e.g., via SOPS_AGE_KEY_FILE env var or default ~/.config/sops/age/keys.txt).
Implementation Detail: Update and encrypt the secrets file with the K3s token:
Bash

# Run from NixOS Config Repo root: /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs
# Ensure K3S_TOKEN is exported via direnv from .env
# Ensure SOPS_AGE_KEY_FILE is set or private key is in ~/.config/sops/age/keys.txt
if [ -z "$K3S_TOKEN" ]; then echo "Error: K3S_TOKEN is not set." >&2; exit 1; fi
echo "Encrypting K3S_TOKEN into ./k3s-cluster/secrets/secrets.yaml..."
# Use --set for idempotency (updates existing or adds new); uses config from .sops.yaml
sops --set '["k3s_token"] "'"$K3S_TOKEN"'"' ./k3s-cluster/secrets/secrets.yaml > ./k3s-cluster/secrets/secrets.yaml.tmp && \
  mv ./k3s-cluster/secrets/secrets.yaml.tmp ./k3s-cluster/secrets/secrets.yaml
echo "K3S_TOKEN encrypted."
# Verify (requires private key access)
echo "Verifying decryption (requires private key):"
sops -d ./k3s-cluster/secrets/secrets.yaml | grep 'k3s_token:'
[ ] 4.4: Encrypt Tailscale Auth Key

[ ] Add Tailscale auth key to secrets file
[ ] Encrypt with sops
Test: Verify encryption with sops -d ./k3s-cluster/secrets/secrets.yaml | grep tailscale_authkey. Commit the encrypted file to Git.
Context: Encrypts the $TAILSCALE_AUTH_KEY for use by sops-nix to configure services.tailscale.authKeyFile. Choose a reusable or ephemeral key from your Tailscale admin console based on your desired node lifecycle. Requires age private key access.
Implementation Detail: Update and encrypt the secrets file with the Tailscale auth key:
Bash

# Run from NixOS Config Repo root
# Ensure TAILSCALE_AUTH_KEY is exported via direnv from .env
# Ensure SOPS_AGE_KEY_FILE is set or private key is available
if [ -z "$TAILSCALE_AUTH_KEY" ]; then echo "Error: TAILSCALE_AUTH_KEY is not set." >&2; exit 1; fi
echo "Encrypting TAILSCALE_AUTH_KEY into ./k3s-cluster/secrets/secrets.yaml..."
sops --set '["tailscale_authkey"] "'"$TAILSCALE_AUTH_KEY"'"' ./k3s-cluster/secrets/secrets.yaml > ./k3s-cluster/secrets/secrets.yaml.tmp && \
  mv ./k3s-cluster/secrets/secrets.yaml.tmp ./k3s-cluster/secrets/secrets.yaml
echo "TAILSCALE_AUTH_KEY encrypted."
# Verify (requires private key access)
echo "Verifying decryption (requires private key):"
sops -d ./k3s-cluster/secrets/secrets.yaml | grep 'tailscale_authkey:'
[ ] 4.5: Encrypt Hetzner API Token

Context: The Hetzner API token ($HETZNER_TOKEN) is needed by Kubernetes components (CCM, CSI, CA) deployed via Flux, not directly by NixOS during bootstrap.
Decision: Do not encrypt the $HETZNER_TOKEN in the NixOS secrets file (./k3s-cluster/secrets/secrets.yaml).
Implementation Detail: This token will be handled as a Kubernetes secret, managed either via Infisical (synced by its operator) or by creating a SOPS-encrypted Secret manifest directly in the Flux repository (see Phase 9.1). This keeps K8s infrastructure credentials separate from NixOS bootstrap secrets.
[ ] 4.6: Configure Sops-Nix Integration

[ ] Create ./k3s-cluster/secrets.nix to integrate with sops-nix
[ ] Configure secret paths and permissions
Test: Verify file syntax with nix-instantiate --parse ./k3s-cluster/secrets.nix. Runtime test requires the private age key on the target node.
Context: This NixOS module configures the sops-nix service on nodes. It specifies the location of the node's private age key (age.keyFile) needed for decryption at activation time and defines which encrypted keys from secrets.yaml should be decrypted into files under /run/secrets/ with appropriate ownership/permissions for services like k3s and tailscaled.
Security Critical: The private age key (/var/lib/sops-nix/key.txt) must be securely provisioned to each node before NixOS attempts to activate sops-nix. Use deploy-rs secrets management, secure cloud-init, or manual placement during initial setup.
Implementation Detail: Create the file ./k3s-cluster/secrets.nix:
Nix

# ./k3s-cluster/secrets.nix
{ config, lib, pkgs, ... }:
{
  sops = {
    # Path on the TARGET NODE where the PRIVATE age key must exist.
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Ensure this key has permissions readable only by root (e.g., 0400).

    # Path to the encrypted secrets file relative to this .nix file
    defaultSopsFile = ./secrets/secrets.yaml;

    # Define NixOS-level secrets needed by services
    secrets = {
      # Makes value of 'k3s_token' in secrets.yaml available at /run/secrets/k3s_token
      k3s_token = {
        owner = config.users.users.root.name;
        group = config.users.groups.root.name;
        mode = "0400"; # Readable only by root (for k3s service)
      };
      # Makes value of 'tailscale_authkey' available at /run/secrets/tailscale_authkey
      tailscale_authkey = {
        owner = config.users.users.tailscaled.user;
        group = config.users.users.tailscaled.group;
        mode = "0400"; # Readable only by tailscaled user/group
      };
      # DO NOT define hetzner_api_token here
    };
  };

  # Ensure the directory for the age private key exists with root-only access
  # The key file itself must be placed here securely by external means.
  systemd.tmpfiles.rules = [
    "d /var/lib/sops-nix 0700 root root - -"
  ];
}
Phase 5: Hetzner Infrastructure Setup
Context: Create the foundational cloud resources in your Hetzner project using the hcloud CLI, driven by variables exported via direnv and potentially wrapped by just commands.

[ ] 5.1: Upload SSH Key to Hetzner

Context: Registers your admin public SSH key ($ADMIN_SSH_PUBLIC_KEY) with Hetzner Cloud under the name specified by $HETZNER_SSH_KEY_NAME. This allows passwordless SSH access to the servers you create.
Implementation Detail: Upload the SSH key using the hcloud CLI:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
if [ -z "$ADMIN_SSH_PUBLIC_KEY" ] || [ -z "$HETZNER_SSH_KEY_NAME" ]; then echo "Error: ADMIN_SSH_PUBLIC_KEY or HETZNER_SSH_KEY_NAME not set." >&2; exit 1; fi
echo "Uploading SSH key '${HETZNER_SSH_KEY_NAME}' to Hetzner..."
echo "$ADMIN_SSH_PUBLIC_KEY" | hcloud ssh-key create --name "$HETZNER_SSH_KEY_NAME" --public-key-from-stdin
Test: Verify key is listed: hcloud ssh-key list | grep "$HETZNER_SSH_KEY_NAME".
[ ] 5.2: Create Private Network

Context: Creates the isolated Layer 2/3 network ($PRIVATE_NETWORK_NAME) with the specified IP range (10.0.0.0/16) and adds a subnet for server attachment in your target region ($HETZNER_NETWORK_ZONE, e.g., us-east). This is essential for secure and performant k3s inter-node communication.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Creating Hetzner private network '${PRIVATE_NETWORK_NAME:-k3s-net}'..."
just create-hetzner-network # This command wraps the necessary hcloud calls
Test: Verify network and subnet details: hcloud network describe ${PRIVATE_NETWORK_NAME:-k3s-net}.
[ ] 5.3: Create Firewall

Context: Sets up the Hetzner Cloud Firewall ($FIREWALL_NAME) and applies inbound rules to control traffic reaching your nodes. Rules allow essential traffic (SSH from admin, K8s internal communication on private net, Ingress traffic) while blocking unwanted access.
Implementation Detail: Use the just command (ensure its definition includes rules for all planned services: SSH, K8s API, Kubelet, Etcd, Flannel/Cilium, Traefik, Netdata):
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Creating Hetzner firewall '${FIREWALL_NAME:-k3s-fw}' and applying rules..."
# This command wraps multiple 'hcloud firewall add-rule' calls
just create-hetzner-firewall
Test: Verify firewall rules carefully: hcloud firewall describe ${FIREWALL_NAME:-k3s-fw}. Ensure ports like 80, 443, 6443, 2379, 2380, 10250, 51820(UDP), 8472(UDP), 19999, etc., have appropriate source IP restrictions (Admin IP, Private Net 10.0.0.0/16, or 0.0.0.0/0 for public ingress).
[ ] 5.4: Create Placement Group (Optional)

Context: Creates a 'spread' placement group ($PLACEMENT_GROUP_NAME) to request that Hetzner places your VMs on distinct underlying physical hosts, enhancing resilience. Recommended for multi-node setups.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
if [ -n "$PLACEMENT_GROUP_NAME" ]; then # Only run if variable is set
  echo "Creating Hetzner placement group '${PLACEMENT_GROUP_NAME}'..."
  just create-hetzner-placement-group
else
  echo "Skipping placement group creation (PLACEMENT_GROUP_NAME not set)."
fi
Test: If created, verify: hcloud placement-group list | grep "$PLACEMENT_GROUP_NAME".
Phase 6: Build and Upload Hetzner Image
Context: Generate the bootable NixOS image artifact containing your base configuration and k3s components, compress it, upload it to accessible storage, and register it with Hetzner Cloud. Automate this via CI/CD (GitHub Actions) for consistency.

[ ] 6.1: Build Hetzner Image

Context: Compiles the k3s-node-cloud-builder NixOS configuration defined in your flake.nix into a raw disk image (result/disk.raw). This image is generic and relies on cloud-init user-data for role specification. May require --impure if flake reads environment variables directly.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Building Hetzner K3s Node Image (Flake Output: hetznerK3sNodeImage)..."
just build-k3s-image # Runs: nix build .#hetznerK3sNodeImage --impure
Test: ls -lh result/disk.raw exists after successful build. Check build logs for errors.
[ ] 6.2: Compress Image

Context: Compresses the raw disk image using zstd for faster uploads/downloads.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Compressing image artifact..."
just compress-k3s-image # Runs: zstd result/disk.raw -o hetzner-k3s-image.zst
Test: ls -lh hetzner-k3s-image.zst exists.
[ ] 6.3: Upload Image

Context: Host the compressed image (hetzner-k3s-image.zst) publicly via HTTPS. GitHub Releases is used in the example. Critical: Hetzner requires a direct, non-redirecting download URL. GitHub release asset URLs sometimes don't work directly; test thoroughly or consider using public S3/B2/etc.
Implementation Detail (Example using GitHub CLI - adapt for CI):
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
TAG_NAME="k3s-image-$(date +%Y%m%d-%H%M%S)"
# Use GITHUB_USER and FLUX_REPO (or a dedicated NixOS repo variable)
GITHUB_REPO_FULL="${GITHUB_USER}/${FLUX_REPO}"
echo "Creating GitHub release $TAG_NAME in $GITHUB_REPO_FULL..."
gh release create "$TAG_NAME" --repo "$GITHUB_REPO_FULL" \
    --notes "NixOS K3s image build for Hetzner - ${TAG_NAME}" \
    ./hetzner-k3s-image.zst # Upload artifact with release creation
echo "Verifying direct download URL..."
# Attempt to construct or retrieve the direct download URL (VERIFY THIS MANUALLY!)
# IMAGE_DOWNLOAD_URL=$(gh release view "$TAG_NAME" --repo "$GITHUB_REPO_FULL" --json assets --jq '.assets[] | select(.name=="hetzner-k3s-image.zst") | .url') # This might be browser URL
IMAGE_DOWNLOAD_URL="https://github.com/$GITHUB_REPO_FULL/releases/download/$TAG_NAME/hetzner-k3s-image.zst" # More likely direct URL structure
echo "Potential Direct Download URL: $IMAGE_DOWNLOAD_URL"
if curl --output /dev/null --silent --head --fail -L "$IMAGE_DOWNLOAD_URL"; then
  echo "URL appears directly downloadable via curl."
  export IMAGE_DOWNLOAD_URL="$IMAGE_DOWNLOAD_URL"
else
  echo "ERROR: URL $IMAGE_DOWNLOAD_URL may NOT be directly downloadable by Hetzner. Check URL or use alternative storage." >&2
  # exit 1 # Fail the process if URL seems invalid
fi
Test: Manually verify the generated ${IMAGE_DOWNLOAD_URL} works with curl -L -o test.zst <URL>.
[ ] 6.4: Register Image in Hetzner

Context: Instructs Hetzner Cloud to download the image from ${IMAGE_DOWNLOAD_URL}, decompress it, and make it available as a custom image named ${HETZNER_IMAGE_NAME} for server creation.
Implementation Detail: Use the just command with the verified URL:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
if [ -z "$IMAGE_DOWNLOAD_URL" ]; then echo "Error: IMAGE_DOWNLOAD_URL not set/exported from previous step." >&2; exit 1; fi
echo "Registering image '${HETZNER_IMAGE_NAME:-my-k3s-image-v1}' in Hetzner from URL..."
# The just command runs: hcloud image create --name ... --url ...
just register-k3s-image "$IMAGE_DOWNLOAD_URL"
Test: hcloud image list | grep "${HETZNER_IMAGE_NAME:-my-k3s-image-v1}". Wait for status available. Update ${HETZNER_IMAGE_NAME} in your flake's devShell shellHook if you used a versioned name like my-k3s-image-${TAG_NAME}.
Phase 7: Node Provisioning
Context: Create the Hetzner VMs using the registered NixOS image, attaching cloud resources, applying labels, and passing cloud-init user-data to define the node's role (control or worker).

[ ] 7.1: Provision Control Plane Node (hetzner-control-01)

Context: Creates the initial master node using the parameters exported via direnv and the create-control-node just recipe. Applies labels k8s-cluster=${K3S_CLUSTER_NAME} and k8s-nodepool=control-plane. Passes cloud-init data to write /etc/nixos/k3s_role with control.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Provisioning control plane node 'hetzner-control-01'..."
just create-control-node
Test: hcloud server list --selector k8s-nodepool=control-plane. Server status becomes running. hcloud server describe hetzner-control-01 shows correct image, type, labels, network, firewall.
[ ] 7.2: Wait for Control Plane Node to Boot

Context: Allow time for the VM boot, cloud-init script execution (writing role file), NixOS activation (reading role file, enabling correct k3s service via selector), network setup (including Tailscale).
Implementation Detail: Use SSH check loop:
Bash

# Run from local machine
CONTROL_NODE_NAME="hetzner-control-01"
CONTROL_NODE_IP=$(hcloud server ip $CONTROL_NODE_NAME)
ADMIN_USER=${ADMIN_USERNAME:-nixos}
echo "Waiting for $CONTROL_NODE_NAME ($CONTROL_NODE_IP) SSH..."
until ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $ADMIN_USER@$CONTROL_NODE_IP exit; do
  sleep 5 && echo -n ".";
done; echo " SSH OK."
# Optional: Check Tailscale status (e.g., ping Tailscale IP)
# ssh $ADMIN_USER@$CONTROL_NODE_IP "tailscale status"
Test: Successful SSH login.
[ ] 7.3: Verify K3s Server is Running

Context: Confirm the k3s-role-selector service ran successfully, enabled k3s.service, and the node registered itself with the Kubernetes API. Fetch the admin kubeconfig.
Implementation Detail:
Bash

# Run from local machine
CONTROL_IP=$(hcloud server ip hetzner-control-01)
ADMIN_USER=${ADMIN_USERNAME:-nixos}
echo "Verifying k3s server on $CONTROL_NODE_NAME..."
# Check role selector log
ssh $ADMIN_USER@$CONTROL_IP "sudo journalctl -u k3s-role-selector --no-pager -n 20"
# Check k3s service status
ssh $ADMIN_USER@$CONTROL_IP "sudo systemctl status k3s.service"
echo "Waiting for K3s API readiness on node..."
until ssh $ADMIN_USER@$CONTROL_IP "sudo kubectl get node $CONTROL_NODE_NAME --kubeconfig /etc/rancher/k3s/k3s.yaml" &>/dev/null; do sleep 5 && echo -n "."; done; echo " API OK."
echo "Fetching kubeconfig..."
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
just get-kubeconfig # Saves to ~/.kube/config.k3s
export KUBECONFIG=~/.kube/config.k3s
echo "Verifying node $CONTROL_NODE_NAME Ready status via kubectl..."
kubectl wait --for=condition=Ready node/$CONTROL_NODE_NAME --timeout=5m
Test: Role selector log shows "Configuring as k3s control plane". systemctl status k3s.service is active/running. kubectl get node hetzner-control-01 shows Ready.
[ ] 7.4: Note Control Plane Private IP

Context: Double-check the assigned Hetzner private IP against the address configured in NixOS (k3sCommonSpecialArgs.k3sControlPlaneAddr). They must match for workers to connect.
Implementation Detail:
Bash

# Run from local machine
HCLOUD_PRIVATE_IP=$(hcloud server describe hetzner-control-01 -o json | jq -r '.private_net[0].ip')
CONFIG_PRIVATE_IP=${K3S_CONTROL_PLANE_ADDR:-10.0.0.2} # Get from env var used by Nix
echo "Hetzner Assigned Private IP: $HCLOUD_PRIVATE_IP"
echo "Configured Control Plane IP: $CONFIG_PRIVATE_IP"
if [ "$HCLOUD_PRIVATE_IP" != "$CONFIG_PRIVATE_IP" ]; then
  echo "CRITICAL WARNING: IPs differ! Update NixOS k3sCommonSpecialArgs.k3sControlPlaneAddr in flake.nix to match $HCLOUD_PRIVATE_IP and rebuild image/redeploy nodes." >&2
  # Consider exiting here if strict matching is required
fi
Test: IPs match.
[ ] 7.5: Provision Initial Worker Node (hetzner-worker-static-01)

Context: Creates the first worker node using the same image. Cloud-init user-data sets the role to worker. Applies labels k8s-cluster and k8s-nodepool=static-workers. Uses ${WORKER_VM_TYPE}.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Provisioning static worker node 'hetzner-worker-static-workers-1'..."
# Uses default pool 'static-workers' and default WORKER_VM_TYPE
just create-worker-node 1 pool="static-workers"
Test: hcloud server list --selector k8s-nodepool=static-workers.
[ ] 7.6: Wait for Worker Node to Boot

Context: Allow time for boot, cloud-init (role set to 'worker'), NixOS activation, k3s-agent start.
Implementation Detail: Monitor status and test SSH:
Bash

# Run from local machine
WORKER_NODE_NAME="hetzner-worker-static-workers-1" # Matches default just command naming
WORKER_NODE_IP=$(hcloud server ip $WORKER_NODE_NAME)
ADMIN_USER=${ADMIN_USERNAME:-nixos}
echo "Waiting for $WORKER_NODE_NAME ($WORKER_NODE_IP) SSH..."
until ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 $ADMIN_USER@$WORKER_NODE_IP exit; do
  sleep 5 && echo -n ".";
done; echo " SSH OK."
Test: Successful SSH login.
[ ] 7.7: Verify Worker Node Joins Cluster

Context: The k3s agent service (enabled by role selector) connects to the control plane ($K3S_CONTROL_PLANE_ADDR) using the shared token ($K3S_TOKEN via sops-nix).
Implementation Detail: Check using kubectl locally:
Bash

# Run from local machine
export KUBECONFIG=~/.kube/config.k3s
WORKER_NODE_NAME="hetzner-worker-static-workers-1"
echo "Verifying worker node '$WORKER_NODE_NAME' registration..."
until kubectl get node $WORKER_NODE_NAME &>/dev/null; do sleep 5 && echo -n "."; done; echo " Node Registered."
echo "Verifying node '$WORKER_NODE_NAME' Ready status..."
kubectl wait --for=condition=Ready node/$WORKER_NODE_NAME --timeout=5m
kubectl get nodes -o wide # Show both nodes
# Optional: Check agent logs on worker
# ssh $ADMIN_USER@$WORKER_NODE_IP "sudo systemctl status k3s-agent.service"
# ssh $ADMIN_USER@$WORKER_NODE_IP "sudo journalctl -u k3s-agent --no-pager -n 50"
Test: kubectl get nodes shows both hetzner-control-01 (role control-plane,master) and hetzner-worker-static-workers-1 (role <none> or worker) as Ready.
Phase 8: Flux Setup and GitOps Configuration
Context: Install FluxCD into the cluster and configure it to manage the cluster state declaratively based on manifests stored in your Flux Git repository (!kube-flux), enabling GitOps workflows. Configure SOPS for decrypting secrets stored in Git.

[ ] 8.1: Configure Kubernetes Access

Context: Ensure kubectl on your local machine is configured to talk to the newly created Hetzner k3s cluster.
Implementation Detail:
Bash

# Ensure KUBECONFIG points to the file saved by 'just get-kubeconfig'
export KUBECONFIG=~/.kube/config.k3s
echo "Current kubectl context:"
kubectl config current-context
echo "Cluster nodes:"
kubectl get nodes
Test: Commands run without errors and show the correct cluster context and nodes.
[ ] 8.2: Prepare Existing Flux Repository (!kube-flux)

Context: Ensure the designated path (clusters/hetzner/) and its subdirectories for different component categories exist in your Flux Git repo branch (hetzner-cluster or main).
Implementation Detail: (Structure created in step 2.2). Verify:
Bash

# Run from local machine
ls -d /home/evan/2_Dev/2.1_Homelab/\!kube-flux/clusters/hetzner/{core,infrastructure,apps,observability,security,delivery,registry,secrets-sync,backup}/
Test: All planned subdirectories exist.
[ ] 8.3: Bootstrap Flux

Context: Installs Flux controllers (Source, Kustomize, Helm, Notification) into the flux-system namespace and sets up synchronization with your Git repo path (clusters/hetzner). Requires GitHub credentials/token.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
# Ensure GITHUB_USER, GITHUB_TOKEN, FLUX_REPO env vars are sourced
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Bootstrapping Flux..."
# This command runs flux bootstrap github ...
just bootstrap-flux
Test: Verify controllers start: kubectl get pods -n flux-system. Check initial sync status: flux check --kubeconfig=$KUBECONFIG, flux get sources git -A, flux get kustomizations -A. The main flux-system kustomization should reconcile successfully.
[ ] 8.4: Configure Flux SOPS Integration

Context: Allows Flux controllers to decrypt SOPS-encrypted manifests stored in Git using your private age key, which is stored securely as a K8s secret.
Implementation Detail:
Create sops-age Secret: Store the private age key ($AGE_PRIVATE_KEY) in a K8s secret. HANDLE THE PRIVATE KEY SECURELY.
Bash

# Run from local machine where AGE_PRIVATE_KEY is available securely
if [ -z "$AGE_PRIVATE_KEY" ]; then echo "Error: AGE_PRIVATE_KEY env var not set." >&2; exit 1; fi
echo "Creating 'sops-age' secret in 'flux-system' (contains PRIVATE key)..."
echo -n "$AGE_PRIVATE_KEY" | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin
# Immediately clear variable or history if needed
unset AGE_PRIVATE_KEY
# Verify secret exists BUT DO NOT PRINT ITS CONTENT
kubectl get secret sops-age -n flux-system
Configure Flux Kustomization: Edit the main Flux Kustomization manifest in your Git repo (!kube-flux/clusters/hetzner/flux-system/gotk-sync.yaml or similar) and add the decryption: block:
YAML

# In !kube-flux/clusters/hetzner/flux-system/gotk-sync.yaml
# ... inside spec: ...
  decryption:
    provider: sops
    secretRef:
      name: sops-age # Points to the K8s secret created above
# ...
Commit and push this change. Flux will reconcile its own configuration.
Test: Monitor Flux logs (flux logs --level=info -n flux-system -l app=kustomize-controller) for messages indicating SOPS decryption is enabled. Test decryption with a SOPS-encrypted manifest in Phase 9.
[ ] 8.5+: Create Flux Kustomizations (Hierarchy)

Context: Define the deployment structure and dependencies within Flux using Kustomization CRDs for each category of components.
Implementation Detail: In the Flux repo (!kube-flux/clusters/hetzner/), create the top-level Kustomization YAML files referencing their respective subdirectories and declaring dependencies:
core.yaml -> ./core
infrastructure.yaml -> ./infrastructure, dependsOn: [core]
secrets-sync.yaml -> ./secrets-sync, dependsOn: [infrastructure]
registry.yaml -> ./registry, dependsOn: [infrastructure, secrets-sync]
apps.yaml -> ./apps, dependsOn: [infrastructure, secrets-sync, registry]
observability.yaml -> ./observability, dependsOn: [apps]
security.yaml -> ./security, dependsOn: [infrastructure]
delivery.yaml -> ./delivery, dependsOn: [apps]
backup.yaml -> ./backup, dependsOn: [infrastructure, secrets-sync] Create corresponding placeholder kustomization.yaml files inside each subdirectory (e.g., infrastructure/kustomization.yaml). Example infrastructure.yaml (top-level CR):
YAML

# !kube-flux/clusters/hetzner/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infrastructure # This name is used in dependsOn
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/hetzner/infrastructure # Points to subdirectory
  prune: true
  sourceRef: { kind: GitRepository, name: flux-system }
  dependsOn:
    - name: core # Depends on core namespaces
  timeout: 5m
  healthChecks: # Optional: wait for key components
    - { apiVersion: apps/v1, kind: DaemonSet, name: hcloud-csi-node, namespace: kube-system }
    - { apiVersion: apps/v1, kind: Deployment, name: hcloud-cloud-controller-manager, namespace: kube-system }
Test: Commit the structure and top-level Kustomization CRs to Git. Run flux get kustomizations -A. Observe the dependency order and reconciliation status (they will likely stall initially waiting for manifests in the subdirectories).
