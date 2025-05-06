{ config, lib, pkgs, specialArgs, ... }:

let
  # Use the same environment variable as in k3s-control.nix for consistency
  privateInterface = let
    fromEnv = builtins.getEnv "HETZNER_PRIVATE_IFACE";
  in
    if fromEnv != "" then fromEnv else "ens10"; # Using ens10 as per env vars
in {
  # Define the k3s agent service unit
  systemd.services.k3s-agent = {
    description = "Lightweight Kubernetes (Agent)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${pkgs.k3s}/bin/k3s agent";
      KillMode = "process";
      Delegate = true;
      LimitNOFILE = 1048576;
      LimitNPROC = "infinity";
      LimitCORE = "infinity";
      TasksMax = "infinity";
      TimeoutStartSec = 0;
      Restart = "always";
      RestartSec = 5;
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
  sops.secrets.k3s_token = { 
    sopsFile = ../secrets/secrets.yaml; 
    owner = "root"; 
    group = "root"; 
    mode = "0400"; 
  };

  # Worker firewall rules
  networking.firewall.allowedTCPPorts = [ 10250 ]; # Kubelet
  networking.firewall.allowedUDPPorts = [ 8472 51820 ]; # Flannel VXLAN / WireGuard

  # Add kubectl for debugging
  environment.systemPackages = with pkgs; [ kubectl ];
}