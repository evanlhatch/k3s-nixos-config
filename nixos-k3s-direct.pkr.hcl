packer {
  required_plugins {
    hcloud = {
      version = "< 2.0.0"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
  default   = "${env("HETZNER_API_TOKEN")}"
}

# Hardcoded SSH public key
variable "ssh_public_key" {
  type    = string
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDRoa3k+/c6nIFLQHo4XYROMFzRx8j+MoRcrt0FmH8/BxAPpDH55SFMM2CY46LEH14M/+W0baSHhQjX//PEL93P5iN3uIlf9+I6aQr8Fi4F3c5susHqGmIWGTIEridVhEqzOQKDv/S9L1K3sDbjMYBXFyYo95dTIzYaJoxFsBF6cwxuscnKM/vb3eidYctZ61GukFvIkUTMRhO2KsEbc4RCslpTCdYgu7nkHiyCJZW7e37bRJ4AJwnjjX5ObP648wQ2UA0PpYLBUr0JQK6iQTAjwIHLNJheHYaGRf4IHP6sp9YSeY/IqnKMd4aEQd64Too1wMIsWyez9SIwgcH4fyNT"
}

variable "server_type" {
  type    = string
  default = "cpx31"
}

variable "location" {
  type    = string
  default = "ash"  # Ashburn (US East)
}

# Use a local variable for timestamp to avoid formatdate function
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

variable "snapshot_name" {
  type    = string
  default = "cpx31-nixos-k3s"
}

locals {
  nixos_version   = "24.11"
  nixpkgs_version = "branch-off-24.11"
}

source "hcloud" "nixos-k3s" {
  token        = "${var.hcloud_token}"
  rescue       = "linux64"  # This is crucial - boots into rescue mode
  image        = "debian-12"
  location     = "${var.location}"
  server_type  = "${var.server_type}"
  ssh_username = "root"
  snapshot_name = "${var.snapshot_name}-${local.timestamp}"
  snapshot_labels = {
    os          = "nixos"
    nixos       = local.nixos_version
    k3s         = "true"
  }
  
  # Add temporary SSH key for Packer to use
  temporary_key_pair_type = "rsa"
  temporary_key_pair_bits = 4096
}

build {
  sources = ["source.hcloud.nixos-k3s"]

  # Upload the installation script
  provisioner "file" {
    source      = "setup-nixos-k3s-direct.sh"
    destination = "/tmp/install.sh"
  }

  # Execute the installation script
  provisioner "shell" {
    inline = [
      "set -e",
      "echo 'System information:'",
      "uname -a",
      "free -h",
      "df -h",
      "chmod +x /tmp/install.sh",
      "echo 'Running installation script...'",
      "bash -x /tmp/install.sh",
      "echo 'Installation completed. Creating snapshot...'"
    ]
  }
}