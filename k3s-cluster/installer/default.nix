{ config, lib, pkgs, modulesPath, specialArgs ? {}, inputs ? {}, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    # Need sops module if installer uses secrets (e.g., Tailscale)
    # inputs.sops-nix.nixosModules.sops  # Uncomment when inputs are properly passed
    # Optional: Include base profile for common tools/Tailscale in installer
    # ../profiles/base-server.nix # Be careful with dependencies
  ];
  
  environment.systemPackages = with pkgs; [ 
    git 
    vim 
    curl 
    wget 
    parted 
    gptfdisk 
    disko 
    k3s
    nixos-install-tools
    htop
    tmux
    jq
    yq
    iotop
    lsof
    tcpdump
    iptables
  ];
  
  services.openssh.enable = true; # Enable SSH daemon
  services.openssh.settings.PermitRootLogin = "yes"; # Allow root login via SSH key
  users.users.root.initialPassword = ""; # Disable root password login
  
  # Get SSH public key from environment or use default
  users.users.root.openssh.authorizedKeys.keys = let
    fromEnv = builtins.getEnv "ADMIN_SSH_PUBLIC_KEY";
  in
    if fromEnv != "" then [ fromEnv ] else [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRoa3k+/c6nIFLQHo4XYROMFzRx8j+MoRcrt0FmH8/BxAPpDH55SFMM2CY46LEH14M/+W0baSHhQjX//PEL93P5iN3uIlf9+I6aQr8Fi4F3c5susHqGmIWGTIEridVhEqzOQKDv/S9L1K3sDbjMYBXFyYo95dTIzYaJoxFsBF6cwxuscnKM/vb3eidYctZ61GukFvIkUTMRhO2KsEbc4RCslpTCdYgu7nkHiyCJZW7e37bRJ4AJwnjjX5ObP648wQ2UA0PpYLBUr0JQK6iQTAjwIHLNJheHYaGRf4IHP6sp9YSeY/IqnKMd4aEQd64Too1wMIsWyez9SIwgcH4fyNT"
    ];
  
  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Get state version from environment or use default
  system.stateVersion = let 
    fromEnv = builtins.getEnv "NIXOS_STATE_VERSION";
  in 
    if fromEnv != "" then fromEnv else "24.05";

  # If including Tailscale in installer:
  # services.tailscale = { enable = true; package = pkgs.tailscale; authKeyFile = config.sops.secrets.tailscale_authkey.path; };
  # sops.secrets.tailscale_authkey = { sopsFile = ../secrets/secrets.yaml; }; # Needs sops key on installer media or different handling
}