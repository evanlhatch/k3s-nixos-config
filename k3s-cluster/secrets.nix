{ config, lib, pkgs, ... }: {
  sops = {
    # IMPORTANT: Ensure the agent key is present on the target system at this path!
    age.keyFile = "/var/lib/sops-nix/key.txt";
    # Use SSH host key as identity? Requires setup.
    # age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    defaultSopsFile = ./secrets/secrets.yaml; # Relative to this file's location
    secrets = {
      k3s_token = {
         # Needed by roles/k3s-control.nix and roles/k3s-worker.nix
         owner = config.users.users.root.name; # k3s service runs as root
         group = config.users.groups.root.name;
         mode = "0400"; # Readable only by root
       };
      tailscale_authkey = {
         # Needed by modules/tailscale.nix
         owner = "root"; # Tailscale service typically runs as root
         group = "root";
         mode = "0400";
       };
      # Add other NixOS-level secrets here if defined in secrets.yaml
    };
  };
  # Ensure the key directory exists with correct permissions
  systemd.tmpfiles.rules = [
     "d /var/lib/sops-nix 0700 root root - -"
   ];
}