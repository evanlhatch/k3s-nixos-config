# ./k3s-cluster/modules/infisical-agent.nix
{
  config,
  lib,
  pkgs,
  specialArgs ? { },
  ...
}:

let
  # These bootstrap credentials come from specialArgs, passed by the Flake nixosConfiguration
  # The Flake nixosConfiguration, in turn, gets them from ENV vars set by nixos-everywhere.sh
  infisicalBootstrapCfg =
    specialArgs.infisicalBootstrap or {
      clientIdFileContent = ""; # Should cause failure if not provided
      clientSecretFileContent = ""; # Should cause failure if not provided
      infisicalAddress = "https://app.infisical.com"; # Default public Infisical
    };
in
{
  # Ensure Infisical CLI/Agent package is available
  environment.systemPackages = [ pkgs.infisical ]; # 'infisical' package provides the CLI/agent

  # Create directories and write bootstrap credential files securely
  systemd.tmpfiles.rules = [
    "d /etc/infisical 0750 root root - -" # For agent.yaml and cred files
    "f /etc/infisical/client-id 0400 root root - ${infisicalBootstrapCfg.clientIdFileContent}"
    "f /etc/infisical/client-secret 0400 root root - ${infisicalBootstrapCfg.clientSecretFileContent}"
    "d /run/infisical-secrets 0750 root root - -" # For rendered secrets
  ];

  environment.etc."infisical/agent.yaml" = {
    mode = "0400"; # Readable only by root (agent runs as root)
    text = ''
      infisical:
        address: "${infisicalBootstrapCfg.infisicalAddress}" # Use the passed address
      auth:
        type: "universal-auth"
        config:
          client-id_file: /etc/infisical/client-id
          client-secret_file: /etc/infisical/client-secret
          # remove_client_secret_on_read: true # Consider for enhanced security after agent starts

      # Optional: Define sinks for the Infisical access token itself if other tools need it.
      # sinks:
      #   - type: "file"
      #     config:
      #       path: "/run/infisical-secrets/infisical_access_token"
      #       permissions: "0400"

      templates:
        - destination_path: /run/infisical-secrets/k3s_token
          template_content: |
            {{ secret "/k3s-bootstrap" "K3S_TOKEN" }}  # Your preferred path and secret name in Infisical
          config:
            permissions: "0400" # Readable by root (K3s service)
            # polling_interval: "300s" # Optional: how often to check for updates
            # execute: { command: "systemctl try-restart k3s.service k3s-agent.service", timeout: 30 } # Optional: restart service on change

        - destination_path: /run/infisical-secrets/tailscale_join_key
          template_content: |
            {{ secret "/k3s-bootstrap" "TAILSCALE_AUTH_KEY" }} # Your preferred path and secret name in Infisical
          config:
            permissions: "0400" # Readable by root (K3s service for --vpn-auth-file)
            # polling_interval: "300s"
            # execute: { command: "...", timeout: 30 }
    '';
  };

  systemd.services.infisical-agent = {
    description = "Infisical Agent Daemon (manages runtime secrets)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target" # Ensure network is up
      "systemd-tmpfiles-setup.service" # Ensure /etc/infisical files are written
    ];
    wants = [ "network-online.target" ];

    # This service MUST successfully provide secrets BEFORE K3s attempts to start
    before = [
      "k3s.service"
      "k3s-agent.service"
    ];
    # Consider also ConditionPathExists for the client-id/secret files for robustness

    serviceConfig = {
      Type = "simple"; # Infisical agent runs as a foreground daemon
      ExecStart = ''
        ${pkgs.infisical}/bin/infisical-agent --config /etc/infisical/agent.yaml daemon start
      '';
      Restart = "on-failure";
      RestartSec = "10s";
      User = "root"; # Agent needs to write to /run and read /etc
      # StandardOutput = "journal"; # Good for logging
      # StandardError = "journal";
    };
  };
}
