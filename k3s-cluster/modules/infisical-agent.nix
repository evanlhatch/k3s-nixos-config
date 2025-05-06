# k3s-cluster/modules/infisical-agent.nix
# Module for Infisical Agent configuration
{ config, lib, pkgs, ... }:

{
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