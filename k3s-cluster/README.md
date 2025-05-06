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