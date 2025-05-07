# NixOS K3s Cluster on Hetzner Cloud with Tailscale CNI and Infisical Agent

This directory contains the NixOS configuration specific to the K3s Kubernetes cluster running on Hetzner Cloud, managed within the parent NixOS flake at `/home/evan/2_Dev/2.1_Homelab/!k3s-nixos-configs`. It uses a generic builder pattern (`lib/make-k3s-node`) for consistency.

## Key Features

- **Tailscale Integration**: Uses K3s's built-in Tailscale VPN integration (`--vpn-auth`) as the primary mechanism for node-to-node and pod networking, replacing Flannel.
- **Secret Management**: Uses the Infisical Agent on nodes (especially autoscaled ones) with an embedded, least-privilege bootstrap credential (Universal Auth). Runtime secrets like k3s_token and tailscale_authkey are fetched by the agent.
- **Role-Specific Images**: Builds dedicated images for control plane and worker nodes, with appropriate configurations baked in.

## Directory Structure

- `lib/`: Generic node builder function (`make-k3s-node.nix`).
- `modules/`: Reusable NixOS service modules (Tailscale, Infisical Agent, Disko).
- `profiles/`: Common node profiles (`base-server.nix`).
- `roles/`: k3s role specifics (`k3s-control.nix`, `k3s-worker.nix`).
- `locations/`: Environment specifics (`hetzner.nix`, `local.nix`).
- `hardware-configs/`: Machine-specific hardware files (for local nodes).
- `nodes/`: Configurations used for building specific artifacts (e.g., Hetzner image).
- `installer/`: Configuration for the local USB installer ISO.
- `secrets/`: Encrypted secrets definition (`secrets.yaml`) managed by sops-nix (for build-time secrets).
- `.sops.yaml`: SOPS configuration for this directory.

## Secret Management

This cluster uses a hybrid approach to secret management:

1. **Build-time Secrets**: Managed by sops-nix for secrets needed during the NixOS build process.
2. **Runtime Bootstrap Secrets**: Managed by Infisical Agent for node bootstrap (k3s_token, tailscale_authkey).
3. **Kubernetes Secrets**: Managed by Infisical Kubernetes Operator for application secrets.

## Networking

The cluster uses Tailscale as the primary networking layer:

1. **Node-to-Node Communication**: Secured via Tailscale VPN.
2. **Pod Networking**: Uses Tailscale CNI integration instead of Flannel.
3. **Network Policies**: Enforced via Tailscale ACLs rather than Kubernetes NetworkPolicy.

## Usage

See the main `./justfile` for common build, deployment, and management commands related to this cluster. Node definitions and build outputs are configured in `./flake.nix`.

## Detailed Setup Guide

### 1. Set Up Infisical for Secret Management

Before building images, you need to set up Infisical for secret management:

1. Create an Infisical Machine Identity with Universal Auth:
   - Log in to Infisical and create a new Machine Identity
   - Select Universal Auth as the authentication method
   - Grant it read-only access to `/evan-institute/k3s-bootstrap` path
   - Copy the Client ID and Client Secret

2. Add the credentials to your `.env` file:
   ```bash
   export INFISICAL_CLIENT_ID="your-client-id"
   export INFISICAL_CLIENT_SECRET="your-client-secret"
   export INFISICAL_ADDRESS="https://app.infisical.com"
   ```

3. Ensure your bootstrap secrets are stored in Infisical:
   - `k3s_token`: The K3s cluster token
   - `tailscale_join_key`: The Tailscale auth key

4. Run the setup script to test your credentials:
   ```bash
   ./setup-infisical.sh
   ```

### 2. Build and Register Images

The NixOS images include the Infisical Agent and Tailscale integration:

```bash
# Build the control plane image
just build-control-image

# Build the worker image
just build-worker-image

# Compress and register the control plane image with Hetzner Cloud
just register-control-image

# Compress and register the worker image with Hetzner Cloud
just register-worker-image
```

### 3. Create Nodes Using Custom Images

Once the images are registered with Hetzner Cloud:

```bash
# Create a control plane node using the custom image
just create-control-node-from-image

# Create a worker node using the custom image
just create-worker-node-from-image
```

### 4. Access the Cluster

After the nodes are created and joined the cluster:

```bash
# Get the kubeconfig using Tailscale DNS
just get-kubeconfig
```

### 5. Networking Details

- Nodes communicate via Tailscale VPN using K3s's built-in integration
- Pod networking uses Tailscale CNI instead of Flannel
- Network policies are enforced via Tailscale ACLs rather than Kubernetes NetworkPolicy
- Firewall rules are simplified to allow Tailscale traffic (UDP 41641)

### 6. Secret Management Details

- **Bootstrap Secrets**: Managed by Infisical Agent on each node
- **Runtime Secrets**: Fetched from Infisical by the agent and rendered to `/run/infisical-secrets/`
- **Kubernetes Secrets**: Managed by Infisical Kubernetes Operator (deployed separately)