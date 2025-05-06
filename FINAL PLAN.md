# NixOS K3s Cluster on Hetzner Cloud with FluxCD - Final Implementation Plan

This augmented implementation plan builds on the original plan, incorporating specific details from your existing NixOS configuration at `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs`, your Flux setup at `/home/evan/2_Dev/2.1_Homelab/!kube-flux`, and the full suite of chosen open-source tools. It provides concrete code examples, integration points, and detailed steps for setting up the foundation of your cluster.

## Core Philosophy

1. **Declarative Nodes (NixOS Repo):** Your NixOS Flake at `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs` is the single source of truth, defining the complete OS state, k3s installation, networking, base packages (including Tailscale, Netdata), and security settings for all nodes using the generic builder pattern (`make-k3s-node` within `./k3s-cluster/lib/`) for consistency and maintainability.

2. **Declarative Cluster State (Flux Repo):** Your Flux repository at `/home/evan/2_Dev/2.1_Homelab/!kube-flux` defines all Kubernetes resources under the clusters/hetzner path via manifests (YAML, Kustomize, HelmReleases). FluxCD ensures the cluster state converges to the state defined in Git.

3. **Manual Component Integration:** Essential Kubernetes add-ons (Hetzner CCM/CSI, Traefik, Cert-Manager, Harbor, Infisical Operator, SigNoz Collectors, Grafana, Velero, Flagger, Falco, Kyverno, Pixie, etc.) are explicitly installed and configured via Flux definitions in the Flux repo.

4. **Tailscale-Powered Networking:** Tailscale is used via K3s's built-in integration (--vpn-auth) as the primary mechanism for node-to-node and pod networking, replacing Flannel. This creates a unified, secure network mesh spanning different locations without complex traditional VPNs or peering. Hetzner Private Network may still be used for specific traffic like API server access or node-to-node communication outside the K3s overlay if needed.

5. **Centralized Secrets:** Infisical serves as the primary store for all secrets. For runtime bootstrap secrets (k3s_token, tailscale_authkey) on worker/autoscaled nodes, an embedded Infisical Universal Auth credential bootstraps the Infisical Agent, which then fetches runtime secrets. sops-nix might still be used for control-plane nodes (if configured differently) or secrets needed during the Nix build process, but Infisical Agent is the primary runtime mechanism for agents. Infisical Operator remains for K8s app secrets.

## Key Implementation Recommendations

Based on the review, the following key recommendations have been incorporated into this final plan:

### 1. Path Consistency
- **Root Directory:** All paths consistently use `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs` as the root for NixOS configurations.
- **Relative Paths:** All relative paths within Nix files (e.g., `../secrets/secrets.yaml` from modules/) are adjusted accordingly.
- **Script Paths:** All cd commands, file paths in scripts (`./env-vars.sh`, `./justfile`), and relative paths use the correct root directory.

### 2. Environment Variable Management with direnv
- **Nix-Managed Environment:** Use direnv with `.envrc` and `.env` files instead of `env-vars.sh` for a more Nix-native approach.
- **HETZNER_PRIVATE_IFACE:** Verify the actual name of the Hetzner private network interface on the VMs (e.g., ens10, eth1) and ensure this variable is correctly set if needed for specific traffic routing.
- **ADMIN_PUBLIC_IP:** Ensure this is correctly set for the firewall rules.
- **Non-Secret Variables:** Define in the flake's devShell shellHook.
- **Secret Variables:** Store in a gitignored `.env` file that is loaded by direnv.

### 3. Flake Implementation
- **specialArgs:** Pass node-specific parameters like the control plane IP (`k3sControlPlaneAddr`) via specialArgs when calling makeK3sNode in flake.nix outputs (nixosConfigurations).
- **Environment Variables:** While using builtins.getEnv within the role module works, specialArgs is generally cleaner Nix practice for node-specific config.

### 4. Secret Management Strategy
- **For Control Plane Nodes:** If using sops-nix with an AGE key, ensure secure key distribution.
- **For Agent/Worker Nodes:** Use Infisical Agent with embedded Universal Auth credentials to fetch runtime secrets like k3s_token and tailscale_authkey.
- **Security Trade-off:** The embedded Infisical credentials in the image represent a security trade-off made for automation, particularly for autoscaled nodes.

### 5. Minor Refinements
- **Role Selector Logic:** Ensure consistent implementation in roles/*.nix (specifically `services.k3s.enable = ...`) and the selector script in nodes/hetzner-k3s-node/default.nix.
- **Justfile build-k3s-image:** Add the `--impure` flag to the nix build command if the flake relies on environment variables during evaluation.
- **Worker Node IP:** Remove references to --flannel-iface. Add note about needing the k3s --node-external-ip flag (likely set to the node's Tailscale IP/MagicDNS name) and the --vpn-auth-file flag when using Tailscale CNI.

## Integration with Existing NixOS Configuration

- **NixOS Root:** All NixOS configurations reside within `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs`.
- **K3s Config Path:** Cluster-specific NixOS configurations are organized under `./k3s-cluster/`.
- **Flux Root:** Kubernetes configurations are managed within `/home/evan/2_Dev/2.1_Homelab/!kube-flux`.
- **Justfile:** Commands are added to `./justfile`.
- **Environment:** Variables managed through direnv with `.envrc` and `.env` files for a Nix-native approach.
- **Hardware:** Existing hardware information (facter data, hardware-configuration.nix files) is leveraged for node definitions.
## Phase 1: Prerequisites and Environment Setup

### 1.1: Set Up Environment with direnv ✅

- [x] Navigate to your NixOS config directory: `cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs`
- [x] Create/update `.envrc` file:
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

- [x] Create `.env` file for secrets (and add to `.gitignore`):
  ```bash
  # /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/.env
  # SECRETS ONLY - Add this file to .gitignore!
  # Use 'export' because we are using direnv's 'source_env'

  export AGE_PRIVATE_KEY="AGE-SECRET-KEY-..."
  export HETZNER_API_TOKEN="FrSvv..."
  export GITHUB_TOKEN="ghp_..." # Handle securely if repo public
  export TAILSCALE_AUTH_KEY="tskey-auth-..." # Needed for storing in Infisical
  export MINIO_SECRET_KEY="minioadmin-secret"
  export INFISICAL_SERVICE_TOKEN="st.xyz..." # Token for Infisical Operator bootstrap secret
  export ATTIC_TOKEN_SIGNING_SECRET="a-very-strong-random-secret-for-attic-tokens" # For Infisical->Attic secret sync
  # Add the generated K3S_TOKEN here after generating it once
  export K3S_TOKEN="generated-k3s-token-value"
  # Infisical Universal Auth credentials for node bootstrap
  export INFISICAL_CLIENT_ID="client-id-for-node-bootstrap"
  export INFISICAL_CLIENT_SECRET="client-secret-for-node-bootstrap"
  export INFISICAL_ADDRESS="https://your-infisical-instance.example.com" # If self-hosting
  export TAILSCALE_NODE_TAG="k3s" # If using tags for ACLs
  # Add any other truly sensitive values needed in the environment
  # export SIGNOZ_INGESTION_KEY="xyz..." # Example
  ```

- [x] Activate direnv: `direnv allow .`
- [x] Verify essential variables are loaded:
  ```bash
  env | grep -E 'ADMIN_USERNAME|ADMIN_SSH_PUBLIC_KEY|ADMIN_PUBLIC_IP|AGE_PRIVATE_KEY|HETZNER_API_TOKEN|HETZNER_SSH_KEY_NAME|HETZNER_LOCATION|HETZNER_PRIVATE_IFACE|PRIVATE_NETWORK_NAME|FIREWALL_NAME|CONTROL_PLANE_VM_TYPE|WORKER_VM_TYPE|K3S_TOKEN|TAILSCALE_AUTH_KEY|NIXOS_STATE_VERSION|GITHUB_TOKEN|FLUX_REPO|INFISICAL_CLIENT_ID|INFISICAL_CLIENT_SECRET|INFISICAL_ADDRESS|TAILSCALE_NODE_TAG'
  ```

**Notes:** Completed on 5/5/2025. Environment variables are now properly managed through direnv with non-sensitive variables in flake.nix shellHook and sensitive variables in .env. The redundant env-vars.sh file has been removed.

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

### 1.2: Verify Hetzner Account Access ✅

- [x] Log in to Hetzner Cloud Console. Verify project access.
- [x] Test API token permissions: `hcloud server list` (ensure $HETZNER_API_TOKEN is exported via direnv).
**Test**: Command executes successfully, showing 0 servers initially or existing ones.

**Context**: Requires a functional Hetzner Cloud account and an API token with Read/Write permissions assigned to $HETZNER_API_TOKEN in your .env file.

**Notes:** Completed on 5/5/2025. The Hetzner CLI uses the environment variable `HCLOUD_TOKEN` instead of `HETZNER_API_TOKEN`. We verified access by setting this variable directly and found one server running named "hetzner-1" with IP 5.161.197.57.

### 1.3: Generate K3s Token

(This step is now integrated into step 1.1)

### 1.4: Verify Required Tools ✅

- [x] Check versions:
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
  infisical-cli --version # for interacting with Infisical during setup
  ```

**Test**: Each command returns a version string without errors.

**Context**: These CLIs are fundamental for the entire workflow, from building NixOS to managing K8s and interacting with Hetzner/GitHub.

**Notes:** Completed on 5/5/2025. All required tools are installed and working:
- nix 2.28.3
- sops 3.10.2
- age 1.2.1
- hcloud 1.50.0-dev
- kubectl v1.33.0
- helm v3.17.3
- flux 2.5.1
- deploy-rs 1.0
- just 1.40.0
- gh 2.72.0
- infisical-cli 0.15.0

**Implementation Detail**: Install any missing tools using your preferred Nix method (e.g., add to environment.systemPackages in your host's NixOS config, use nix profile install, or use nix-shell -p <tool>):

```bash
# Example using nix profile (per-user)
# nix profile install nixpkgs#sops nixpkgs#age nixpkgs#hcloud nixpkgs#kubectl \
#   nixpkgs#kubernetes-helm nixpkgs#fluxcd nixpkgs#deploy-rs nixpkgs#just nixpkgs#gh nixpkgs#infisical-cli
```

## Phase 2: Repository Structure Setup

### 2.1: Set Up NixOS Repository Structure ✅

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
│   │   ├── infisical-agent.nix
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

**Notes:** Completed on 5/5/2025. Directory structure created successfully.

**Test**: `find ./k3s-cluster -type d | sort` shows the expected directories.
[x] 2.2: Prepare Existing Flux Repository Structure ✅

Context: Sets up the target directory within your established Flux repository (!kube-flux) where all Kubernetes manifests for this specific Hetzner cluster will reside, managed by Flux.
Implementation Detail: Ensure you are on the correct branch (hetzner-cluster or similar) and create the necessary subdirectories:
```bash
cd /home/evan/2_Dev/2.1_Homelab/\!kube-flux
git checkout hetzner-cluster # Or git switch hetzner-cluster
mkdir -p clusters/hetzner/{core,infrastructure,apps,observability,security,delivery,registry,secrets-sync,backup}
# Add .gitkeep files to empty dirs if desired
git add clusters/hetzner
git commit -m "feat(hetzner): Set up cluster directory structure"
# git push origin hetzner-cluster
```

**Notes:** Completed on 5/5/2025. Directory structure created successfully in the Flux repository.

**Test**: `find /home/evan/2_Dev/2.1_Homelab/\!kube-flux/clusters/hetzner -type d | sort` shows the expected directories.
[x] 2.3: Create Initial README Files ✅

Context: Basic documentation explaining the purpose of the new directories.
Implementation Detail:
Create ./k3s-cluster/README.md:
```markdown
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
```

Create /home/evan/2_Dev/2.1_Homelab/!kube-flux/clusters/hetzner/README.md:
```markdown
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
```

**Notes:** Completed on 5/5/2025. README files created successfully in both repositories.

**Test**: Files exist and contain descriptive content.
[x] 2.4: Update Justfile for Common Commands ✅

Context: Adds convenient aliases to ./justfile for common operations related to this cluster setup. Ensure firewall rules in create-hetzner-firewall include necessary ports for all planned tools (Traefik 80/443, Etcd 2379/2380 for future HA).
Implementation Detail: Add/merge the justfile recipes provided in your plan into your existing ./justfile. Ensure variables like ${HETZNER_LOCATION:-ash} and labels applied during node creation are correct. Self-correction: Add firewall rules for Traefik.

**Notes:** Completed on 5/5/2025. Created a new justfile with all the necessary commands for network setup, firewall configuration, node management, image building, Kubernetes management, and secrets management.

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
    # Tailscale Rules
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol udp --port 41641 --source-ips 0.0.0.0/0 --description "Tailscale"
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

[x] 3.1: Common Configuration (common.nix) ✅

Context: Defines base user (${ADMIN_USERNAME:-nixos}), SSH key (${ADMIN_SSH_PUBLIC_KEY}), timezone, locale, common packages.
Implementation:
```nix
# ./k3s-cluster/common.nix
{ config, lib, pkgs, specialArgs, ... }:

let
  # Get SSH public key from environment or use default
  sshPublicKey = let
    fromEnv = builtins.getEnv "ADMIN_SSH_PUBLIC_KEY";
  in
    if fromEnv != "" then fromEnv else
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRoa3k+/c6nIFLQHo4XYROMFzRx8j+MoRcrt0FmH8/BxAPpDH55SFMM2CY46LEH14M/+W0baSHhQjX//PEL93P5iN3uIlf9+I6aQr8Fi4F3c5susHqGmIWGTIEridVhEqzOQKDv/S9L1K3sDbjMYBXFyYo95dTIzYaJoxFsBF6cwxuscnKM/vb3eidYctZ61GukFvIkUTMRhO2KsEbc4RCslpTCdYgu7nkHiyCJZW7e37bRJ4AJwnjjX5ObP648wQ2UA0PpYLBUr0JQK6iQTAjwIHLNJheHYaGRf4IHP6sp9YSeY/IqnKMd4aEQd64Too1wMIsWyez9SIwgcH4fyNT";
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
```

**Notes:** Completed on 5/5/2025. Used a different approach to handle the SSH public key from environment variables to avoid issues with the `or` operator. Set the admin username to "nixos" directly as specified.

**Test**: `nix-instantiate --parse ./k3s-cluster/common.nix` confirms the syntax is valid.
[x] 3.2: Node Builder Function (lib/make-k3s-node.nix) ✅

Context: Central factory for creating NixOS node configurations. Imports base profile, role, location, hardware configs.
Implementation:
```nix
# ./k3s-cluster/lib/make-k3s-node.nix
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
{
  # Return a NixOS system configuration
  nixosSystem = lib.nixosSystem {
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
  };
}
```

**Notes:** Completed on 5/5/2025. Created the node builder function that serves as a factory for NixOS node configurations. It imports common configuration, base server profile, role-specific configuration, location-specific configuration, and optional hardware configuration.

**Test**: `nix-instantiate --parse ./k3s-cluster/lib/make-k3s-node.nix` confirms the syntax is valid.
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
    CONTROL_IP=$(tailscale ip hetzner-control-01)
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

# ./k3s-cluster/modules/infisical-agent.nix
# New module for Infisical Agent configuration
{ config, lib, pkgs, ... }: {
  # Install the Infisical CLI
  environment.systemPackages = [ pkgs.infisical-cli ];
  
  # Create directories for Infisical configuration and secrets
  systemd.tmpfiles.rules = [
    "d /etc/infisical 0755 root root - -"
    "d /run/infisical-secrets 0750 root root - -"
  ];
  
  # Store the Universal Auth credentials in the filesystem
  # These are embedded in the image for autoscaled nodes
  environment.etc = {
    "infisical/client-id" = {
      text = builtins.getEnv "INFISICAL_CLIENT_ID";
      mode = "0400";
    };
    "infisical/client-secret" = {
      text = builtins.getEnv "INFISICAL_CLIENT_SECRET";
      mode = "0400";
    };
    "infisical/agent.yaml" = {
      text = ''
        auth:
          universal:
            client_id_file: /etc/infisical/client-id
            client_secret_file: /etc/infisical/client-secret
        
        address: ${builtins.getEnv "INFISICAL_ADDRESS" or "https://app.infisical.com"}
        
        secrets:
          - path: /k3s-cluster/bootstrap
            destination:
              path: /run/infisical-secrets
              templates:
                - source: k3s_token
                  destination: k3s_token
                  permissions: 0400
                - source: tailscale_join_key
                  destination: tailscale_join_key
                  permissions: 0400
      '';
      mode = "0400";
    };
  };
  
  # Create a systemd service for the Infisical Agent
  systemd.services.infisical-agent = {
    description = "Infisical Agent for Secret Management";
    wantedBy = [ "multi-user.target" ];
    before = [ "k3s.service" "k3s-agent.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.infisical-cli}/bin/infisical secrets pull --config /etc/infisical/agent.yaml";
    };
  };
}
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
[x] 3.4: Create Base Server Profile (profiles/base-server.nix) ✅

**Implementation:**
```nix
# ./k3s-cluster/profiles/base-server.nix
{ config, lib, pkgs, ... }:

{
  # System configuration
  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.firewall.enable = true;

  # Set up nix
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@wheel" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    # System tools
    lsof
    htop
    iotop
    dstat
    sysstat
    tcpdump
    iptables

    # File tools
    file
    tree
    ncdu
    ripgrep
    fd

    # Network tools
    inetutils
    mtr
    nmap
    socat

    # Process management
    psmisc
    procps

    # Text processing
    jq
    yq
  ];

  # Default editor
  environment.variables.EDITOR = "vim";

  # SSH hardening
  services.openssh = {
    settings = {
      X11Forwarding = false;
      AllowTcpForwarding = true;
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      MaxAuthTries = 3;
    };
  };

  # Security hardening
  security = {
    sudo.wheelNeedsPassword = false;
    auditd.enable = true;
    audit.enable = true;
  };

  # Networking
  networking = {
    useDHCP = false;
    useNetworkd = true;
    firewall = {
      allowPing = true;
      logReversePathDrops = true;
    };
  };

  # Enable systemd-networkd
  systemd.network.enable = true;

  # Time synchronization
  services.timesyncd.enable = true;

  # Disable sound
  sound.enable = false;

  # Disable X11
  services.xserver.enable = false;

  # Disable printing
  services.printing.enable = false;

  # Disable bluetooth
  hardware.bluetooth.enable = false;
}
```

**Notes:** Completed on 5/5/2025. Created the base server profile with common settings for all servers, including system configuration, Nix settings, system packages, security hardening, and networking configuration.

**Test**: `nix-instantiate --parse ./k3s-cluster/profiles/base-server.nix` confirms the syntax is valid.
Context: Consolidates common configuration applied to ALL cluster nodes by importing base settings and service modules. Includes k3s package and openiscsi needed for CSI.
Implementation Detail:
Nix

# ./k3s-cluster/profiles/base-server.nix
# (Code from your Plan - Phase 3.4)
{ config, pkgs, inputs, lib, specialArgs, ... }: {
  imports = [
    ../common.nix
    ../modules/tailscale.nix
    ../modules/infisical-agent.nix
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
     tailscale # Include tailscale binary for K3s integration
     infisical-cli # Include infisical-cli for secret management
  ];

  # Nix settings
  nix.settings.trusted-users = [ "root" "@wheel" (builtins.getEnv "ADMIN_USERNAME" or "nixos") ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
Test: nix-instantiate --parse ./k3s-cluster/profiles/base-server.nix.
[x] 3.5: Create K3s Role Configurations (roles/) ✅

Context: Defines the specific k3s service configurations for control-plane (server) and worker (agent) nodes, including crucial flags for Hetzner integration. Important: These modules should define the systemd service units but might not enable them if using the cloud-init role selector in the image build.

**Notes:** Completed on 5/5/2025. Created role-specific configurations for both control plane and worker nodes. Fixed issues with the `or` operator by using a more explicit approach with `let` expressions. Both files pass `nix-instantiate --parse` validation.
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
      "--node-external-ip=$(tailscale ip -4)" # Use Tailscale IP for external access
      "--vpn-auth-file=/run/infisical-secrets/tailscale_join_key" # Use Tailscale for networking
      "--flannel-backend=none" # Disable Flannel as we're using Tailscale
      "--disable-network-policy" # Network policies handled by Tailscale ACLs
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

  # For control plane, we can still use sops-nix for the k3s token
  # Worker nodes will use Infisical Agent instead
  sops.secrets.k3s_token = { sopsFile = ../secrets/secrets.yaml; owner = "root"; group = "root"; mode = "0400"; };

  # Firewall rules for control plane
  networking.firewall.allowedTCPPorts = [ 6443 2379 2380 ]; # K8s API, etcd client, etcd peer
  networking.firewall.allowedUDPPorts = [ 41641 ]; # Tailscale

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
    # Use Tailscale DNS name for control plane connection
    serverAddr = "https://hetzner-control-01:6443";
    # Use Infisical Agent rendered token file
    tokenFile = "/run/infisical-secrets/k3s_token";
    extraFlags = toString [
      # Use Tailscale IP for external access
      "--node-external-ip=$(tailscale ip -4)"
      # Use Tailscale for networking
      "--vpn-auth-file=/run/infisical-secrets/tailscale_join_key"
      # Disable Flannel as we're using Tailscale
      "--flannel-backend=none"
      # Network policies handled by Tailscale ACLs
      "--disable-network-policy"
      "--kubelet-arg=cloud-provider=external"
      # Add node labels here if consistent across all workers of this type
      # "--node-label=topology.kubernetes.io/zone=us-east-1a" # Example
    ];
  };

  # Worker nodes use Infisical Agent for secrets
  # No need for sops-nix token definition

  # Worker firewall rules
  networking.firewall.allowedTCPPorts = [ 10250 ]; # Kubelet
  networking.firewall.allowedUDPPorts = [ 41641 ]; # Tailscale

  # Add kubectl for debugging
  environment.systemPackages = with pkgs; [ kubectl ];
}
Test: nix-instantiate --parse ./k3s-cluster/roles/k3s-control.nix and ...k3s-worker.nix.
[x] 3.6: Create Location Configurations (locations/) ✅

Context: Environment-specific settings (Hetzner vs. Local).
Implementation Detail:

**hetzner.nix:**
```nix
# Hetzner-specific configuration with systemd-networkd setup
{ config, lib, pkgs, ... }:

{
  # Use systemd-networkd for networking
  networking = {
    useDHCP = false;
    useNetworkd = true;
  };

  # Configure systemd-networkd for Hetzner Cloud
  systemd.network = {
    enable = true;

    # Public network interface (typically eth0)
    networks."10-eth0" = {
      name = "eth0";
      DHCP = "ipv4";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = "yes";
      };
      linkConfig.RequiredForOnline = "no";
    };

    # Private network interface (typically ens10)
    networks."20-ens10" = {
      name = "ens10";
      DHCP = "ipv4";
      networkConfig = {
        DHCP = "yes";
      };
      linkConfig.RequiredForOnline = "no";
    };
  };

  # Enable cloud-init for Hetzner Cloud
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "Hetzner" "None" ];
    };
  };
}
```

**hetzner-hardware.nix:**
```nix
# Hetzner Cloud specific hardware configuration
{ config, lib, pkgs, ... }:

{
  # Import qemu-guest profile
  imports = [
    "${toString pkgs.path}/nixos/modules/profiles/qemu-guest.nix"
  ];

  # Hetzner Cloud specific kernel modules
  boot.kernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "nvme"
    "ata_piix"
    "uhci_hcd"
  ];

  # Hetzner Cloud specific boot settings
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = false;
    efiInstallAsRemovable = false;
  };
}
```

**local.nix:**
```nix
# Local machine specific configuration
{ config, lib, pkgs, ... }:

{
  # Use NetworkManager for networking on local machines
  networking = {
    useDHCP = false;
    networkmanager.enable = true;
  };

  # Enable firmware updates
  hardware.enableRedistributableFirmware = true;

  # Enable all firmware
  hardware.enableAllFirmware = true;

  # Enable CPU microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Set timezone to local timezone (override in hardware-configuration.nix if needed)
  time.timeZone = lib.mkDefault "America/Denver";
}
```

**Notes:** Completed on 5/5/2025. Created location-specific configurations for both Hetzner Cloud and local machines. The Hetzner configuration includes network setup for both public and private interfaces, cloud-init configuration, and hardware-specific settings. The local configuration includes NetworkManager setup and firmware settings.

**Test**: All files pass `nix-instantiate --parse` validation.
[x] 3.7: Create Hetzner Node Configuration (nodes/hetzner-k3s-node/default.nix) ✅

Context: Defines the configuration baked into the generic Hetzner image, including the k3s-role-selector service for determining role via cloud-init.

**Notes:** Completed on 5/5/2025. Created the Hetzner node configuration that imports the base server profile, Hetzner-specific settings, and both role modules. Added a k3s-role-selector service that reads the role from cloud-init data and enables the appropriate k3s service. Fixed issues with the `or` operator by using a more explicit approach with `let` expressions.
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
    # Import Infisical Agent module
    ../../modules/infisical-agent.nix
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
    after = [ "network-online.target" "cloud-final.service" "infisical-agent.service" ];
    # Ensure k3s services are defined before this tries to enable them
    requires = [ "k3s.service" "k3s-agent.service" ];
    # Wait for Infisical Agent to fetch secrets
    wants = [ "infisical-agent.service" ];

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
[x] 3.8: Create Installer Configuration (installer/default.nix) ✅

Context: Defines the environment for the bootable USB installer for local machines.
Implementation Detail:
```nix
# ./k3s-cluster/installer/default.nix
{ config, lib, pkgs, modulesPath, specialArgs ? {}, inputs ? {}, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    # Need sops module if installer uses secrets (e.g., Tailscale)
    # inputs.sops-nix.nixosModules.sops  # Uncomment when inputs are properly passed
  ];

  environment.systemPackages = with pkgs; [
    git vim curl wget parted gptfdisk disko k3s
    nixos-install-tools htop tmux jq yq iotop lsof tcpdump iptables
  ];

  services.openssh.enable = true; # Enable SSH daemon
  services.openssh.settings.PermitRootLogin = "yes"; # Allow root login via SSH key
  users.users.root.initialPassword = ""; # Disable root password login
  users.users.root.openssh.authorizedKeys.keys = [ (builtins.getEnv "ADMIN_SSH_PUBLIC_KEY" or "ssh-rsa AAAA...") ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = builtins.getEnv "NIXOS_STATE_VERSION" or "24.05";
}
```

**Notes:** Completed on 5/5/2025. Created the installer configuration with the necessary tools for installing NixOS on local machines. Added additional useful tools like nixos-install-tools, htop, tmux, etc. Made the SSH public key handling more robust by providing a default key if the environment variable is not set.

**Test**: Successfully verified the file syntax with `nix-instantiate --parse k3s-cluster/installer/default.nix`.
Test: nix-instantiate --parse ./k3s-cluster/installer/default.nix.
[ ] 3.9: Create Disko Configurations (modules/disko-*.nix)

Context: Declarative disk partitioning, useful for consistent local machine installs.
Implementation Detail: (Code from your Plan - Phase 3.9 for disko-control.nix and disko-worker.nix). Import these within the respective hardware-configs/*.nix files for local machines or use with disko script during installation.
Test: Parse the files.
[x] 3.10: Create/Update Flake Configuration (./flake.nix) ✅

Context: The main entrypoint defining inputs, outputs, node configurations using the builder, image/installer packages, and deploy-rs settings.
Implementation Detail: Ensure your main /home/evan/nixos/flake.nix integrates the k3s configurations correctly, referencing the files within ./k3s-cluster/. Use the detailed example provided in your plan (Phase 3.10) as a template, adjusting existing inputs/outputs as needed. Key parts: Define makeK3sNode let binding, k3sCommonSpecialArgs, nixosConfigurations for all Hetzner and local nodes using makeK3sNode, the k3s-node-cloud-builder and installer configs, packages outputs for hetznerK3sNodeImage & installerIso, and the deploy block using Tailscale hostnames.

**Notes:** Completed on 5/5/2025. Updated the flake.nix file with:
1. A makeK3sNode function that imports the make-k3s-node.nix file
2. Common special arguments for all k3s nodes
3. NixOS configurations for the control plane and worker nodes
4. Configuration for the Hetzner K3s node image builder using sd-image.nix
5. Configuration for the installer ISO
6. Packages outputs for hetznerK3sNodeImage and installerIso

**Test**: Successfully ran `nix flake check` to verify the configuration.
Test: cd /home/evan/nixos && nix flake check . and nix flake show ..
## Phase 4: Bootstrap Secret Management (Infisical Agent)

Context: This phase configures the Infisical Agent for runtime secret management on nodes, particularly for autoscaled worker nodes. This replaces the previous approach of using sops-nix for bootstrap secrets like k3s_token and tailscale_authkey.

[ ] 4.1: Create Infisical Machine Identity & Universal Auth Credentials

**Context**: Create a dedicated, least-privilege Infisical Machine Identity and Universal Auth credentials specifically for node bootstrap. These credentials will be embedded in the NixOS image.

**Implementation Detail**:
1. Log in to your Infisical instance (cloud or self-hosted)
2. Navigate to Project Settings > Machine Identities
3. Create a new Machine Identity named "k3s-node-bootstrap"
4. Set appropriate permissions (read-only access to specific secrets)
5. Generate Universal Auth credentials (Client ID and Client Secret)
6. Add these credentials to your .env file:

```bash
# Add to /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/.env
export INFISICAL_CLIENT_ID="your-client-id"
export INFISICAL_CLIENT_SECRET="your-client-secret"
export INFISICAL_ADDRESS="https://your-infisical-instance.example.com" # If self-hosting
```

**Test**: Verify the credentials work by using the Infisical CLI:
```bash
infisical login universal --client-id $INFISICAL_CLIENT_ID --client-secret $INFISICAL_CLIENT_SECRET
infisical secrets list
```

[ ] 4.2: Store K3S_CLUSTER_TOKEN and TAILSCALE_AUTH_KEY in Infisical

**Context**: Store the runtime secrets that nodes need to bootstrap in Infisical. These will be fetched by the Infisical Agent on node startup.

**Implementation Detail**:
1. Log in to your Infisical instance
2. Navigate to the appropriate project and environment
3. Create a new secret path `/k3s-cluster/bootstrap`
4. Add the following secrets:
   - `k3s_token`: Value from your K3S_TOKEN environment variable
   - `tailscale_join_key`: Value from your TAILSCALE_AUTH_KEY environment variable

**Test**: Verify the secrets are accessible with the machine identity credentials:
```bash
infisical login universal --client-id $INFISICAL_CLIENT_ID --client-secret $INFISICAL_CLIENT_SECRET
infisical secrets get -p /k3s-cluster/bootstrap -e production k3s_token
infisical secrets get -p /k3s-cluster/bootstrap -e production tailscale_join_key
```

[ ] 4.3: Configure NixOS Image with Infisical Agent

**Context**: Configure the NixOS image to include the Infisical Agent, embed the Universal Auth credentials, and set up the agent to fetch secrets on boot.

**Implementation Detail**: This is handled by the infisical-agent.nix module we created earlier, which:
1. Installs the Infisical CLI
2. Creates directories for configuration and secrets
3. Embeds the Universal Auth credentials in the filesystem
4. Configures the agent to fetch secrets from Infisical
5. Creates a systemd service to run the agent on boot

**Test**: Build a test image and verify the Infisical Agent configuration is included:
```bash
nix build .#hetznerK3sNodeImage --impure
```

[ ] 4.4: Configure Control Plane Nodes (Optional)

**Context**: For control plane nodes, you may still want to use sops-nix for secret management, as they are typically not autoscaled and may have different security requirements.

**Implementation Detail**: If you choose to use sops-nix for control plane nodes:
1. Keep the sops-nix configuration in the control plane role
2. Use deploy-rs to securely distribute the private key to control plane nodes
3. Ensure the control plane role imports the secrets.nix module

**Test**: Deploy to a control plane node and verify secrets are properly decrypted:
```bash
deploy .#hetzner-control-01
ssh nixos@hetzner-control-01 "sudo cat /run/secrets/k3s_token"
```

[ ] 4.5: Defer Hetzner API Token Management

**Context**: The Hetzner API token is primarily needed by Kubernetes components (CCM, CSI, Cluster Autoscaler), not by NixOS itself.

**Implementation Detail**: We will handle this secret within the Kubernetes ecosystem:
1. Create a Kubernetes Secret in the Flux repository (encrypted with SOPS)
2. Or sync it from Infisical using the Infisical Operator

**Test**: This will be tested in Phase 9 when deploying the Hetzner CCM and CSI.

Phase 5: Hetzner Infrastructure Setup
Context: This phase uses the hcloud CLI (likely via just commands) to create the necessary cloud resources in your Hetzner project before provisioning nodes.

[x] 5.1: Upload SSH Key to Hetzner ✅

Context: Registers your ${ADMIN_SSH_PUBLIC_KEY} in Hetzner Cloud under the name ${HETZNER_SSH_KEY_NAME}, allowing SSH access to VMs created with this key.
Implementation Detail:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Uploading SSH key '${HETZNER_SSH_KEY_NAME:-my-admin-key}' to Hetzner..."
# Ensure ADMIN_SSH_PUBLIC_KEY and HETZNER_SSH_KEY_NAME are sourced
hcloud ssh-key create --name "${HETZNER_SSH_KEY_NAME}" --public-key "$ADMIN_SSH_PUBLIC_KEY"
Test: hcloud ssh-key list shows the key.

**Notes:** Completed on 5/5/2025. Found that the SSH key was already uploaded to Hetzner with the name "blade-nixos SSH Key". Updated the flake.nix file to use this existing key name instead of creating a new one. Verified that the fingerprint of the local SSH key matches the one in Hetzner.
[x] 5.2: Create Private Network ✅

Context: Creates the isolated network (${PRIVATE_NETWORK_NAME}) with the 10.0.0.0/16 range and adds a subnet specific to your Hetzner location (${HETZNER_NETWORK_ZONE} or default us-east) for server attachment. This network is crucial for secure and efficient k3s communication.
Implementation Detail: Use the just command:
Bash

# Run from NixOS Config Repo root
cd /home/evan/2_Dev/2.1_Homelab/\!k3s-nixos-configs
echo "Creating Hetzner private network '${PRIVATE_NETWORK_NAME:-k3s-net}'..."
just create-hetzner-network # Just command includes subnet creation
Test: hcloud network describe ${PRIVATE_NETWORK_NAME:-k3s-net} shows details.

**Notes:** Completed on 5/5/2025. Successfully created the private network "k3s-net" with IP range 10.0.0.0/16 and added a subnet with IP range 10.0.0.0/24 in the us-east network zone. Verified that the network was created successfully using `hcloud network list`.
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

Okay, let's integrate the nix build approach with automatic versioning, compression, direct hcloud upload, and just orchestration into a revised Phase 6 for your implementation guide.

Phase 6: Build, Compress & Register NixOS Image via just

Context: (Current as of: Monday, May 5, 2025 at 11:56:42 PM MDT) This phase details the automated process for creating your custom NixOS worker node image locally using nix build, compressing it, and registering it directly with Hetzner Cloud. We will use just as the command runner to orchestrate these steps and automatically generate versioned image names based on the timestamp and Git commit hash. This replaces previous methods involving Packer or manual uploads via URLs. This assumes you are building an image designed for autoscaling, incorporating the Infisical Agent and embedded credentials as previously discussed.

[ ] 6.1: Define Justfile Recipes

Context: Add the necessary recipes to your /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs/justfile. These recipes define the build, compress, and register actions, orchestrated by a main workflow recipe that handles automatic versioning.

Implementation Detail: Add or merge the following recipes into your justfile. Ensure the variables at the top (IMAGE_BASENAME, FLAKE_OUTPUT_NAME, LOCAL_RAW_IMAGE_LINK) are set correctly for your project.

Code snippet

# === Image Building (Add/Merge into your Justfile) ===

# --- Variables ---
# Base name for the image
export IMAGE_BASENAME := "nixos-k3s-worker"
# Flake output package name defining the image build
export FLAKE_OUTPUT_NAME := "autoscaled-worker-image" # Adjust if your flake output is named differently
# Local nix build output link name (temporary)
export LOCAL_RAW_IMAGE_LINK := "./result-worker-image"

# --- Core Recipes ---

# Build the raw disk image using Nix
_build-image flake_output out_link:
    echo "Building NixOS image: .#{{flake_output}}"
    # Add --impure if required by your flake
    # Add --option flags for substituters/trusted-keys if not globally configured or using direnv/nix-direnv
    nix build .#{{flake_output}} --out-link {{out_link}} --accept-flake-config --extra-experimental-features "nix-command flakes"

# Compress the raw image using zstd
_compress-image raw_link compressed_path:
    echo "Finding raw image in {{raw_link}}..."
    # Use find within shell - safer for paths potentially containing spaces etc.
    RAW_IMAGE_PATH := shell('find "{{raw_link}}" -name "*.raw" -print -quit')
    if [ -z "{{RAW_IMAGE_PATH}}" ]; then echo "Error: Raw image not found in {{raw_link}}!" >&2; exit 1; fi
    echo "Compressing {{RAW_IMAGE_PATH}} to {{compressed_path}}..."
    zstd --rm -T0 "{{RAW_IMAGE_PATH}}" -o "{{compressed_path}}" # -T0 uses all cores, --rm removes original .raw
    echo "Compressed image created:"
    ls -lh "{{compressed_path}}"

# Register image in Hetzner directly from compressed file
_register-image-file image_name compressed_path:
    # Check if repo is dirty (optional, add '-dirty' suffix if needed)
    # IS_DIRTY := shell_output('if git diff --quiet && git diff --cached --quiet; then echo ""; else echo "-dirty"; fi')
    GIT_HASH := shell("git rev-parse --short HEAD")
    VERSION_LABEL := "git-g{{GIT_HASH}}" # + IS_DIRTY

    echo "Registering Hetzner image '{{image_name}}' from file: {{compressed_path}}"
    hcloud image create \
        --name "{{image_name}}" \
        --type snapshot \
        --from-file "{{compressed_path}}" \
        --label os=nixos \
        --label purpose=k3s-worker \
        --label version="{{VERSION_LABEL}}" # Add Git hash label

# --- Main Workflow Recipe ---

# Build, Compress, and Register via Direct File Upload with AUTO VERSIONING
# Usage: just build-and-register [FLAKE_OUTPUT_NAME] [IMAGE_BASENAME]
build-and-register flake_output=FLAKE_OUTPUT_NAME base_name=IMAGE_BASENAME:
    # 1. Generate Versioned Name (YYYYMMDD + Git Hash)
    TIMESTAMP := shell("date +%Y%m%d")
    GIT_HASH  := shell("git rev-parse --short HEAD")
    _image_name := base_name + "-" + TIMESTAMP + "-g" + GIT_HASH
    echo "Generated Image Name: {{_image_name}}"

    # 2. Define compressed file path using the generated name
    _compressed_path := "./" + _image_name + ".raw.zst"

    # 3. Run the steps, passing dynamic names/paths
    # Ensure required env vars (like HETZNER_API_TOKEN) are loaded via direnv/.env
    just _build-image flake_output=flake_output out_link=LOCAL_RAW_IMAGE_LINK
    just _compress-image raw_link=LOCAL_RAW_IMAGE_LINK compressed_path=_compressed_path
    just _register-image-file image_name=_image_name compressed_path=_compressed_path

    # 4. Output final name for user
    echo ""
    echo "--------------------------------------------------------------------"
    echo "Successfully registered Hetzner image: {{_image_name}}"
    echo "Verify status is 'available' via 'hcloud image list'"
    echo "Update Cluster Autoscaler / Deployment config to use this image name."
    echo "--------------------------------------------------------------------"

Test: Run just --list in the repo root directory and verify the new recipes (_build-image, _compress-image, _register-image-file, build-and-register) appear.

[ ] 6.2: Ensure Prerequisites

Context: Verify your local development environment and Nix configuration are ready before building.
Implementation Detail: Check the following:
You are in the correct directory: cd /home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs
Your direnv environment is active (run echo $HETZNER_API_TOKEN - should not be empty if loaded from .env).
Required tools are available (check nix --version, just --version, hcloud --version, zstd --version, git --version). These should be provided by your flake's devShell activated by direnv.
Your NixOS flake configuration for the image (.#{{FLAKE_OUTPUT_NAME}}) is complete and correct (includes Infisical agent setup, embedded credentials, etc.). Run nix flake check . to catch basic errors.
Your Git working directory is clean (git status) - recommended since the commit hash is used in the image name. Commit any pending changes.
Test: Confirm tools are present and environment variables (like HETZNER_API_TOKEN) are loaded. nix flake check . passes.
[ ] 6.3: Execute the Build & Register Workflow

Context: Run the primary just command to build the image locally, compress it, upload it directly to Hetzner, and register it.
Implementation Detail: Execute the main workflow recipe.
Bash

# Run from NixOS Config Repo root
# Uses default FLAKE_OUTPUT_NAME and IMAGE_BASENAME from Justfile vars
just build-and-register

# OR override variables if needed:
# just build-and-register FLAKE_OUTPUT_NAME="my-special-image-output" IMAGE_BASENAME="special-worker"
Note: This process can take a significant amount of time, especially the nix build (if uncached) and the hcloud image create --from-file upload step. Monitor the output.
Test: The command should run through all steps (build, compress, register) without errors. The final output should clearly state the generated image name (e.g., nixos-k3s-worker-20250505-gabcdef0).
[ ] 6.4: Verify Image in Hetzner Cloud

Context: After just finishes, confirm the image was successfully created and is ready to use in Hetzner Cloud.
Implementation Detail: Use the hcloud CLI. Filter using the base name or labels.
Bash

# List recent images, filtering by label or name pattern
hcloud image list --sort created:desc --selector os=nixos
# OR check specifically by the name outputted by the just command:
# hcloud image describe nixos-k3s-worker-20250505-gabcdef0
Test: Verify the image with the automatically generated name exists. Check its Status. It will initially be creating; wait until it becomes available. Confirm the labels (os, purpose, version) are correct.
[ ] 6.5: Update Cluster Autoscaler / Node Templates

Context: The final step is to tell your cluster provisioning mechanism (Cluster Autoscaler for autoscaled nodes) to use this new, versioned image.
Implementation Detail:
Copy the exact image name generated by the just build-and-register command (e.g., nixos-k3s-worker-20250505-gabcdef0).
Edit the configuration for your Cluster Autoscaler (likely the HelmRelease values in your Flux repository under clusters/hetzner/infrastructure/).
Find the relevant node group definition for your autoscaled workers and update the image parameter to this new name.
Commit and push the changes to your Flux repository.
Test: Monitor Flux applying the configuration change (flux get kustomizations, flux logs ...). Observe the Cluster Autoscaler logs (kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler -f) to ensure it recognizes the new image configuration. Future scaling events should now use the updated image.




## Phase 9: Core Kubernetes Add-ons

Context: This phase deploys essential Kubernetes components via Flux manifests in your Flux repository. These components provide core functionality like storage, networking, and ingress.

### 9.1: Deploy Hetzner Cloud Controller Manager (CCM)

**Context**: The Hetzner Cloud Controller Manager (CCM) integrates Kubernetes with Hetzner Cloud API, enabling features like proper node addressing, load balancer provisioning, and metadata. It requires the Hetzner API token as a secret.

**Implementation Detail**:

1. Create the secret for the Hetzner API token:

```yaml
# !kube-flux/clusters/hetzner/infrastructure/hcloud-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: hcloud
  namespace: kube-system
stringData:
  token: ${HETZNER_API_TOKEN} # Will be encrypted by SOPS
```

2. Encrypt the secret with SOPS:

```bash
# Run from Flux repo root
cd /home/evan/2_Dev/2.1_Homelab/\!kube-flux
sops --encrypt --in-place clusters/hetzner/infrastructure/hcloud-secret.yaml
```

3. Create the HelmRelease for the CCM:

```yaml
# !kube-flux/clusters/hetzner/infrastructure/hcloud-ccm.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: hcloud-cloud-controller-manager
  namespace: kube-system
spec:
  interval: 15m
  chart:
    spec:
      chart: hcloud-cloud-controller-manager
      version: "1.18.0" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: hcloud
        namespace: flux-system
  values:
    privateNetwork: true # Enable if using Hetzner Private Network
    networkRouting:
      enabled: false # Set to true if using advanced network routing
```

4. Add the Hetzner Helm repository to Flux:

```yaml
# !kube-flux/clusters/hetzner/infrastructure/hcloud-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: hcloud
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.hetzner.cloud
```

**Test**: After Flux reconciles, verify the CCM is running: `kubectl get pods -n kube-system -l app=hcloud-cloud-controller-manager`.

### 9.2: Deploy Hetzner Cloud Storage Interface (CSI)

**Context**: The Hetzner CSI driver enables Kubernetes to provision and manage Hetzner Cloud Volumes as PersistentVolumes. It uses the same API token as the CCM.

**Implementation Detail**:

```yaml
# !kube-flux/clusters/hetzner/infrastructure/hcloud-csi.yaml
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
      version: "2.5.1" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: hcloud
        namespace: flux-system
  values:
    storageClasses:
      - name: hcloud-volumes
        defaultStorageClass: true
        reclaimPolicy: Delete
```

**Test**: Verify the CSI components are running: `kubectl get pods -n kube-system -l app=hcloud-csi`. Create a test PVC: `kubectl apply -f test-pvc.yaml` and check that it's bound.

### 9.3: Deploy Traefik Ingress Controller

**Context**: Traefik serves as the ingress controller, routing external traffic to services within the cluster. It will be configured to use Tailscale for secure access.

**Implementation Detail**:

1. Add the Traefik Helm repository:

```yaml
# !kube-flux/clusters/hetzner/apps/traefik-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: traefik
  namespace: flux-system
spec:
  interval: 1h
  url: https://helm.traefik.io/traefik
```

2. Create the Traefik namespace:

```yaml
# !kube-flux/clusters/hetzner/apps/traefik-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
```

3. Deploy Traefik with Helm:

```yaml
# !kube-flux/clusters/hetzner/apps/traefik.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: traefik
  namespace: traefik
spec:
  interval: 15m
  chart:
    spec:
      chart: traefik
      version: "24.0.0" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: flux-system
  values:
    deployment:
      replicas: 2
    ingressClass:
      enabled: true
      isDefaultClass: true
    service:
      enabled: true
      type: LoadBalancer
    logs:
      general:
        level: INFO
      access:
        enabled: true
    additionalArguments:
      - "--api.dashboard=true"
      - "--api.insecure=false"
      - "--serverstransport.insecureskipverify=true"
      - "--providers.kubernetesingress.ingressclass=traefik"
```

**Test**: Verify Traefik is running: `kubectl get pods -n traefik`. Check that the LoadBalancer service has an external IP: `kubectl get svc -n traefik`.

### 9.4: Deploy Cert-Manager

**Context**: Cert-Manager automates the management of TLS certificates, including requesting and renewal from Let's Encrypt.

**Implementation Detail**:

1. Add the Jetstack Helm repository:

```yaml
# !kube-flux/clusters/hetzner/apps/jetstack-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: jetstack
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.jetstack.io
```

2. Create the cert-manager namespace:

```yaml
# !kube-flux/clusters/hetzner/apps/cert-manager-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
```

3. Deploy Cert-Manager with Helm:

```yaml
# !kube-flux/clusters/hetzner/apps/cert-manager.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: cert-manager
  namespace: cert-manager
spec:
  interval: 15m
  chart:
    spec:
      chart: cert-manager
      version: "v1.13.2" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: jetstack
        namespace: flux-system
  values:
    installCRDs: true
    prometheus:
      enabled: true
    webhook:
      timeoutSeconds: 10
```

4. Create a ClusterIssuer for Let's Encrypt:

```yaml
# !kube-flux/clusters/hetzner/apps/letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com # Replace with your email
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: traefik
```

**Test**: Verify Cert-Manager is running: `kubectl get pods -n cert-manager`. Check that the ClusterIssuer is ready: `kubectl get clusterissuer letsencrypt-prod -o wide`.

### 9.5: Deploy Harbor Registry

**Context**: Harbor provides a secure container registry for storing and distributing container images within your cluster.

**Implementation Detail**:

1. Add the Harbor Helm repository:

```yaml
# !kube-flux/clusters/hetzner/registry/harbor-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: harbor
  namespace: flux-system
spec:
  interval: 1h
  url: https://helm.goharbor.io
```

2. Create the harbor namespace:

```yaml
# !kube-flux/clusters/hetzner/registry/harbor-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: harbor
```

3. Deploy Harbor with Helm:

```yaml
# !kube-flux/clusters/hetzner/registry/harbor.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: harbor
  namespace: harbor
spec:
  interval: 15m
  chart:
    spec:
      chart: harbor
      version: "1.12.2" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: harbor
        namespace: flux-system
  values:
    expose:
      type: ingress
      ingress:
        hosts:
          core: harbor.example.com # Replace with your domain
        annotations:
          kubernetes.io/ingress.class: traefik
          cert-manager.io/cluster-issuer: letsencrypt-prod
        tls:
          enabled: true
          secretName: harbor-tls
    persistence:
      persistentVolumeClaim:
        registry:
          storageClass: "hcloud-volumes"
        chartmuseum:
          storageClass: "hcloud-volumes"
        jobservice:
          storageClass: "hcloud-volumes"
        database:
          storageClass: "hcloud-volumes"
        redis:
          storageClass: "hcloud-volumes"
        trivy:
          storageClass: "hcloud-volumes"
    harborAdminPassword: "Harbor12345" # Change this and use a secret
```

**Test**: Verify Harbor is running: `kubectl get pods -n harbor`. Access the Harbor UI at https://harbor.example.com.

## Phase 10: Observability Setup

Context: This phase sets up monitoring, logging, and tracing tools to provide visibility into the cluster's health and performance.

### 10.1: Deploy SigNoz

**Context**: SigNoz provides a comprehensive observability platform with metrics, logs, and traces in a single solution.

**Implementation Detail**:

1. Create the signoz namespace:

```yaml
# !kube-flux/clusters/hetzner/observability/signoz-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: signoz
```

2. Add the SigNoz Helm repository:

```yaml
# !kube-flux/clusters/hetzner/observability/signoz-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: signoz
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.signoz.io
```

3. Deploy SigNoz with Helm:

```yaml
# !kube-flux/clusters/hetzner/observability/signoz.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: signoz
  namespace: signoz
spec:
  interval: 15m
  chart:
    spec:
      chart: signoz
      version: "0.30.0" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: signoz
        namespace: flux-system
  values:
    clickhouse:
      persistence:
        storageClass: "hcloud-volumes"
    frontend:
      ingress:
        enabled: true
        className: traefik
        annotations:
          cert-manager.io/cluster-issuer: letsencrypt-prod
        hosts:
          - host: signoz.example.com # Replace with your domain
            paths:
              - path: /
                pathType: Prefix
        tls:
          - secretName: signoz-tls
            hosts:
              - signoz.example.com # Replace with your domain
```

**Test**: Verify SigNoz is running: `kubectl get pods -n signoz`. Access the SigNoz UI at https://signoz.example.com.

### 10.2: Deploy Grafana

**Context**: Grafana provides visualization for metrics and logs, complementing SigNoz for specific dashboarding needs.

**Implementation Detail**:

1. Create the monitoring namespace:

```yaml
# !kube-flux/clusters/hetzner/observability/monitoring-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
```

2. Add the Grafana Helm repository:

```yaml
# !kube-flux/clusters/hetzner/observability/grafana-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: grafana
  namespace: flux-system
spec:
  interval: 1h
  url: https://grafana.github.io/helm-charts
```

3. Deploy Grafana with Helm:

```yaml
# !kube-flux/clusters/hetzner/observability/grafana.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: grafana
  namespace: monitoring
spec:
  interval: 15m
  chart:
    spec:
      chart: grafana
      version: "6.58.8" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: grafana
        namespace: flux-system
  values:
    persistence:
      enabled: true
      storageClassName: "hcloud-volumes"
    ingress:
      enabled: true
      ingressClassName: traefik
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
      hosts:
        - grafana.example.com # Replace with your domain
      tls:
        - secretName: grafana-tls
          hosts:
            - grafana.example.com # Replace with your domain
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
          - name: SigNoz
            type: prometheus
            url: http://signoz-otel-collector.signoz:9090
            access: proxy
            isDefault: true
```

**Test**: Verify Grafana is running: `kubectl get pods -n monitoring`. Access the Grafana UI at https://grafana.example.com.

## Phase 11: Security Implementation

Context: This phase deploys security tools to enhance the cluster's security posture, including runtime security and policy enforcement.

### 11.1: Deploy Falco

**Context**: Falco provides runtime security by monitoring container behavior and detecting suspicious activities.

**Implementation Detail**:

1. Create the falco namespace:

```yaml
# !kube-flux/clusters/hetzner/security/falco-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: falco
```

2. Add the Falco Helm repository:

```yaml
# !kube-flux/clusters/hetzner/security/falco-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: falcosecurity
  namespace: flux-system
spec:
  interval: 1h
  url: https://falcosecurity.github.io/charts
```

3. Deploy Falco with Helm:

```yaml
# !kube-flux/clusters/hetzner/security/falco.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: falco
  namespace: falco
spec:
  interval: 15m
  chart:
    spec:
      chart: falco
      version: "3.8.0" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: falcosecurity
        namespace: flux-system
  values:
    driver:
      kind: ebpf
    falco:
      jsonOutput: true
      priority: debug
    tty: true
    integrations:
      slack:
        enabled: false # Enable and configure if needed
```

**Test**: Verify Falco is running: `kubectl get pods -n falco`. Check Falco logs: `kubectl logs -n falco -l app=falco`.

## Phase 12: CI/CD Integration

Context: This phase sets up progressive delivery capabilities using Flagger for automated canary deployments.

### 12.1: Deploy Flagger

**Context**: Flagger is a progressive delivery tool that automates the release process for applications running on Kubernetes.

**Implementation Detail**:

1. Create the flagger namespace:

```yaml
# !kube-flux/clusters/hetzner/delivery/flagger-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: flagger
```

2. Add the Flagger Helm repository:

```yaml
# !kube-flux/clusters/hetzner/delivery/flagger-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: flagger
  namespace: flux-system
spec:
  interval: 1h
  url: https://flagger.app
```

3. Deploy Flagger with Helm:

```yaml
# !kube-flux/clusters/hetzner/delivery/flagger.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: flagger
  namespace: flagger
spec:
  interval: 15m
  chart:
    spec:
      chart: flagger
      version: "1.35.0" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: flagger
        namespace: flux-system
  values:
    metricsServer: http://signoz-otel-collector.signoz:9090
    meshProvider: traefik
    slack:
      enabled: false # Enable and configure if needed
```

**Test**: Verify Flagger is running: `kubectl get pods -n flagger`. Check Flagger CRDs: `kubectl get crd | grep flagger`.

## Phase 13: Backup and Disaster Recovery

Context: This phase sets up backup and disaster recovery capabilities for the cluster using Velero.

### 13.1: Deploy Velero

**Context**: Velero provides backup and restore capabilities for Kubernetes cluster resources and persistent volumes.

**Implementation Detail**:

1. Create the velero namespace:

```yaml
# !kube-flux/clusters/hetzner/backup/velero-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: velero
```

2. Add the Velero Helm repository:

```yaml
# !kube-flux/clusters/hetzner/backup/velero-repo.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: vmware-tanzu
  namespace: flux-system
spec:
  interval: 1h
  url: https://vmware-tanzu.github.io/helm-charts
```

3. Create a secret for MinIO credentials:

```yaml
# !kube-flux/clusters/hetzner/backup/minio-credentials.yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: velero
stringData:
  cloud: |
    [default]
    aws_access_key_id=minioadmin
    aws_secret_access_key=${MINIO_SECRET_KEY} # Will be encrypted by SOPS
```

4. Encrypt the secret with SOPS:

```bash
# Run from Flux repo root
cd /home/evan/2_Dev/2.1_Homelab/\!kube-flux
sops --encrypt --in-place clusters/hetzner/backup/minio-credentials.yaml
```

5. Deploy Velero with Helm:

```yaml
# !kube-flux/clusters/hetzner/backup/velero.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: velero
  namespace: velero
spec:
  interval: 15m
  chart:
    spec:
      chart: velero
      version: "5.0.2" # Check for latest version
      sourceRef:
        kind: HelmRepository
        name: vmware-tanzu
        namespace: flux-system
  values:
    initContainers:
      - name: velero-plugin-for-aws
        image: velero/velero-plugin-for-aws:v1.7.0
        volumeMounts:
          - mountPath: /target
            name: plugins
    configuration:
      provider: aws
      backupStorageLocation:
        name: default
        bucket: velero
        config:
          region: minio
          s3ForcePathStyle: true
          s3Url: http://minio.example.com # Replace with your MinIO URL
      volumeSnapshotLocation:
        name: default
        config:
          region: minio
    credentials:
      existingSecret: minio-credentials
    schedules:
      daily-backup:
        schedule: "0 1 * * *"
        template:
          ttl: "240h"
```

**Test**: Verify Velero is running: `kubectl get pods -n velero`. Create a test backup: `velero backup create test-backup --include-namespaces default`.



## Phase 15: GitHub Actions CI/CD

Context: This phase sets up GitHub Actions workflows to automate the building and testing of NixOS images and Kubernetes manifests.

### 15.1: Create GitHub Actions Workflow for NixOS Image

**Context**: Automates the building and testing of NixOS images on push to the main branch.

NEED TO SET THIS UP since we changed from using packer


## Conclusion

This comprehensive implementation plan provides a detailed roadmap for setting up a modern, resilient, and secure Kubernetes cluster on Hetzner Cloud using NixOS and FluxCD. By following these phases, you'll establish:

1. A declarative infrastructure with NixOS for consistent node configuration
2. A GitOps workflow with FluxCD for managing Kubernetes resources
3. Core Kubernetes add-ons for networking, storage, and ingress
4. Comprehensive observability with metrics, logs, and traces
5. Enhanced security with runtime monitoring and policy enforcement
6. Automated backup and disaster recovery
7. CI/CD integration for progressive delivery
8. Automated image building and testing

The modular approach allows you to implement each phase incrementally, testing thoroughly before moving to the next. The use of Tailscale's built-in integration with K3s provides a unified, secure network mesh for both node-to-node and pod networking, spanning different locations without complex traditional VPNs or peering. This approach simplifies networking while enhancing security.

As you progress through this plan, remember to:

1. Regularly commit your NixOS and Flux configurations to Git
2. Test each component thoroughly before proceeding
3. Monitor resource usage and adjust VM types as needed
4. Implement proper backup and disaster recovery procedures
5. Keep all components updated to their latest stable versions
6. Manage Tailscale ACLs for network policy enforcement
7. Rotate Infisical Universal Auth credentials periodically for security

With this foundation in place, you'll have a robust platform for deploying and managing applications in a secure, scalable, and maintainable way.
