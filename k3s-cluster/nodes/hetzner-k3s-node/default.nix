# ./k3s-cluster/nodes/hetzner-k3s-node/default.nix
# This defines a generic base for a Hetzner node image that can select its role.
# It would be used by a Flake output that builds an image, e.g.,
# self.nixosConfigurations.k3sGenericHetznerImage.config.system.build.sdImage
{
  config,
  lib,
  pkgs,
  specialArgs,
  inputs,
  ...
}: # Assume inputs is available if sops-nix is used
{
  imports =
    [
      ../../profiles/base-server.nix # Already imports infisical-agent & tailscale
      ../../locations/hetzner.nix # Generic Hetzner settings
      # Import BOTH role modules. The selector service will enable the correct one.
      ../../roles/k3s-control.nix
      ../../roles/k3s-worker.nix
      # Conditionally import sops if this generic image might use it for some secrets
      # (though bootstrap K3s/Tailscale secrets for it should come from Infisical)
    ]
    ++ (lib.optionals (specialArgs.nodeSecretsProvider == "sops") [
      inputs.sops-nix.nixosModules.sops # Make sure 'inputs' is passed to this file correctly
      ../../secrets.nix # Or specialArgs.sopsSecretsNixFile
    ]);

  # This image relies on cloud-init to write /etc/nixos/k3s_role
  # specialArgs (like k3sControlPlaneAddr, nodeSecretsProvider, infisicalBootstrap)
  # must be passed to this configuration when it's evaluated by the Flake for an image build.
  _module.args = lib.intersectAttrs specialArgs {
    k3sControlPlaneAddr = null;
    nodeSecretsProvider = "infisical"; # Default for generic image
    infisicalBootstrap = { }; # Will be filled by Flake if this image uses infisical
    hetznerPublicInterface = null;
    hetznerPrivateInterface = null;
    adminUsername = null; # from common.nix specialArgs
    adminSshPublicKey = null; # from common.nix specialArgs
    isFirstControlPlane = false; # Default for generic image
  };

  networking.hostName = specialArgs.hostname or "k3s-generic-node"; # Default for the image
  services.cloud-init.enable = true;

  systemd.services."k3s-role-selector" = {
    description = "Select K3s role (control/agent) based on /etc/nixos/k3s_role";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "cloud-final.service"
      "infisical-agent.service"
    ];
    requires = [ "infisical-agent.service" ]; # Ensure secrets are present
    serviceConfig = {
      # ... (script as provided in your plan, ensure it's robust) ...
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "k3s-role-selector-script" ''
        set -euo pipefail
        ROLE_FILE="/etc/nixos/k3s_role" # This file is written by cloud-init
        K3S_ROLE="worker"

        if [ -f "$ROLE_FILE" ]; then
            FILE_CONTENT=$(cat "$ROLE_FILE")
            if [ "$FILE_CONTENT" = "control" ] || [ "$FILE_CONTENT" = "worker" ]; then
                K3S_ROLE="$FILE_CONTENT"
            else
                echo "Warning: Invalid content in $ROLE_FILE: '$FILE_CONTENT'. Defaulting to worker." >&2
            fi
        else
            echo "Warning: Role file $ROLE_FILE not found. Defaulting to worker." >&2
        fi

        echo "Role selector: Determined role: $K3S_ROLE"
        if [ "$K3S_ROLE" = "control" ]; then
            echo "Role selector: Enabling k3s server (k3s.service)..."
            systemctl enable --now k3s.service
            systemctl disable --now k3s-agent.service >/dev/null 2>&1 || true
        else # worker (default)
            echo "Role selector: Enabling k3s agent (k3s-agent.service)..."
            systemctl enable --now k3s-agent.service
            systemctl disable --now k3s.service >/dev/null 2>&1 || true
        fi
        echo "Role selector: Done."
      '';
    };
  };
  system.stateVersion = specialArgs.stateVersion or "24.11";
}
