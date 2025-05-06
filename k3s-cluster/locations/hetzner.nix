{ config, lib, pkgs, ... }:

{
  # Hetzner-specific configuration
  
  # Use systemd-networkd for networking
  networking = {
    useDHCP = false;
    useNetworkd = true;
  };
  
  # Configure systemd-networkd for Hetzner Cloud
  systemd.network = {
    enable = true;
    
    # Public network interface (typically eth0)
    networks."10-eth0" = {
      name = "eth0";
      DHCP = "ipv4";
      networkConfig = {
        # Use lib.mkForce to override the default value
        DHCP = lib.mkForce "yes";
        IPv6AcceptRA = "yes";
      };
      # Ensure this interface is considered online even without carrier
      linkConfig.RequiredForOnline = "no";
    };
    
    # Private network interface (typically ens10)
    networks."20-ens10" = {
      name = "ens10";
      DHCP = "ipv4";
      networkConfig = {
        # Use lib.mkForce to override the default value
        DHCP = lib.mkForce "yes";
      };
      # Ensure this interface is considered online even without carrier
      linkConfig.RequiredForOnline = "no";
    };
  };
  
  # Hetzner Cloud specific kernel modules
  boot.kernelModules = [ "virtio_pci" "virtio_scsi" "nvme" "ata_piix" "uhci_hcd" ];
  
  # Hetzner Cloud specific boot settings
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    efiSupport = false;
    efiInstallAsRemovable = false;
  };
  
  # Hetzner Cloud specific filesystem settings
  fileSystems."/" = {
    device = lib.mkForce "/dev/sda1";
    fsType = lib.mkForce "ext4";
  };
  
  # Hetzner Cloud specific swap settings
  swapDevices = [ ];
  
  # Enable cloud-init for Hetzner Cloud
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "Hetzner" "None" ];
    };
  };
  
  # Enable qemu-guest-agent for Hetzner Cloud
  services.qemuGuest.enable = true;
  
  # Firewall settings for Hetzner Cloud
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # SSH
    allowPing = true;
  };
  
  # Set timezone to UTC (using mkForce to override common.nix)
  time.timeZone = lib.mkForce "UTC";
  
  # Disable power management
  powerManagement.enable = false;
  
  # Disable X11
  services.xserver.enable = false;
}