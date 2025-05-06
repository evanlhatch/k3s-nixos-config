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
    wants = [ "network-online.target" ];
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
        '
      '';
    };
  };

  # Crucially: Ensure the role modules DO NOT enable k3s services by default
  # This is achieved by setting services.k3s.enable = false; inside roles/*.nix
  # The selector service will then enable the appropriate service based on the role.

  # Get state version from environment or use default
  system.stateVersion = let 
    fromEnv = builtins.getEnv "NIXOS_STATE_VERSION";
  in 
    if fromEnv != "" then fromEnv else "24.05";
}