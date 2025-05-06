{ config, lib, pkgs, specialArgs, ... }:

let
  # Get control plane IP from environment or use default
  controlPlaneIp = let
    fromEnv = builtins.getEnv "K3S_CONTROL_PLANE_ADDR";
  in
    if fromEnv != "" then fromEnv else "10.0.0.2";
  
  # Get private interface from environment or use default
  privateInterface = let
    fromEnv = builtins.getEnv "HETZNER_PRIVATE_IFACE";
  in
    if fromEnv != "" then fromEnv else "ens10"; # Using ens10 as per env vars
in {
  # Define the k3s server service unit, but don't enable by default
  # Role selector service will enable it if role is 'control'
  systemd.services.k3s = {
    description = "Lightweight Kubernetes (Server)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${pkgs.k3s}/bin/k3s server";
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
  sops.secrets.k3s_token = { 
    sopsFile = ../secrets/secrets.yaml; 
    owner = "root"; 
    group = "root"; 
    mode = "0400"; 
  };

  # Firewall rules for control plane
  networking.firewall.allowedTCPPorts = [ 6443 2379 2380 ]; # K8s API, etcd client, etcd peer
  networking.firewall.allowedUDPPorts = [ ]; # Flannel handled by worker rules or separate module

  # Add essential client tools
  environment.systemPackages = with pkgs; [ kubectl kubernetes-helm fluxcd ];
}