# NixOS K3s Cluster on Hetzner Cloud Justfile

# Default recipe to show help
default:
    @just --list

# Build the K3s node image for Hetzner Cloud (legacy method - disabled)
build-k3s-image-nix:
    nix build .#hetznerK3sNodeImage --impure --option substituters https://cache.nixos.org

# Compress the K3s node image for upload
compress-k3s-image:
    zstd result/disk.raw -o hetzner-k3s-image.zst

# Register the K3s node image with Hetzner Cloud
register-k3s-image:
    hcloud image create --name ${HETZNER_IMAGE_NAME:-my-k3s-image-v1} --type snapshot --description "NixOS K3s Node Image" --from-url ${IMAGE_DOWNLOAD_URL}

# Create Hetzner Cloud network
create-hetzner-network:
    hcloud network create --name ${PRIVATE_NETWORK_NAME:-k3s-net} --ip-range 10.0.0.0/16
    hcloud network add-subnet ${PRIVATE_NETWORK_NAME:-k3s-net} --network-zone ${HETZNER_NETWORK_ZONE:-us-east} --type server --ip-range 10.0.0.0/16

# Create Hetzner Cloud firewall
create-hetzner-firewall:
    hcloud firewall create --name ${FIREWALL_NAME:-k3s-fw}
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 22 --source-ips ${ADMIN_PUBLIC_IP}/32 --description "SSH from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips ${ADMIN_PUBLIC_IP}/32 --description "ICMP from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips 10.0.0.0/16 --description "ICMP from Private Net"

# Create Hetzner Cloud placement group
create-hetzner-placement-group:
    hcloud placement-group create --name ${PLACEMENT_GROUP_NAME:-k3s-placement-group} --type spread

# Create Hetzner Cloud SSH key
create-hetzner-ssh-key:
    hcloud ssh-key create --name "${HETZNER_SSH_KEY_NAME:-k3s-ssh-key}" --public-key-from-file ~/.ssh/id_ed25519.pub

# Create Hetzner Cloud control plane node
create-control-node:
    hcloud server create \
        --name hetzner-control-01 \
        --type ${CONTROL_PLANE_VM_TYPE:-cpx31} \
        --image ${HETZNER_IMAGE_NAME:-my-k3s-image-v1} \
        --ssh-key ${HETZNER_SSH_KEY_NAME:-k3s-ssh-key} \
        --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
        --firewall ${FIREWALL_NAME:-k3s-fw} \
        --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
        --location ${HETZNER_LOCATION:-ash} \
        --label ${CLUSTER_IDENTIFIER:-k8s-cluster=k3s-us-east} \
        --label ${CONTROL_PLANE_POOL:-k8s-nodepool=control-plane} \
        --user-data-from-file ./cloud-init/control-node-user-data.yaml

# Create Hetzner Cloud worker node
create-worker-node:
    hcloud server create \
        --name hetzner-worker-static-01 \
        --type ${WORKER_VM_TYPE:-cpx21} \
        --image ${HETZNER_IMAGE_NAME:-my-k3s-image-v1} \
        --ssh-key ${HETZNER_SSH_KEY_NAME:-k3s-ssh-key} \
        --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
        --firewall ${FIREWALL_NAME:-k3s-fw} \
        --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
        --location ${HETZNER_LOCATION:-ash} \
        --label ${CLUSTER_IDENTIFIER:-k8s-cluster=k3s-us-east} \
        --label ${STATIC_WORKER_POOL:-k8s-nodepool=static-workers} \
        --user-data-from-file ./cloud-init/worker-node-user-data.yaml

# Deploy the NixOS configuration to the control plane node
deploy-control-node:
    deploy --skip-checks --targets hetzner-control-01

# Deploy the NixOS configuration to the worker node
deploy-worker-node:
    deploy --skip-checks --targets hetzner-worker-static-01

# Get the kubeconfig from the control plane node
get-kubeconfig:
    mkdir -p ~/.kube
    scp nixos@hetzner-control-01:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    sed -i 's/127.0.0.1/hetzner-control-01/g' ~/.kube/config
    chmod 600 ~/.kube/config
    echo "Kubeconfig saved to ~/.kube/config"

# Install Flux CD
install-flux:
    flux bootstrap github \
        --owner=${GITHUB_USER:-evanlhatch} \
        --repository=${FLUX_REPO:-kube-flux} \
        --branch=main \
        --path=./clusters/k3s-us-east \
        --personal

# Build the K3s node image for Hetzner Cloud using Packer (rescue mode method)
build-k3s-image: packer-init
    #!/usr/bin/env bash
    export HCLOUD_TOKEN=$(grep HETZNER_API_TOKEN .env | cut -d'"' -f2)
    # No need to pass SSH key as a variable since it's hardcoded in the Packer file
    packer build nixos-k3s.pkr.hcl

# Build the K3s node image using the direct installation method
build-k3s-image-direct: packer-init-direct
    #!/usr/bin/env bash
    export HCLOUD_TOKEN=$(grep HETZNER_API_TOKEN .env | cut -d'"' -f2)
    # No need to pass SSH key as a variable since it's hardcoded in the Packer file
    packer build nixos-k3s-direct.pkr.hcl

# Initialize Packer plugins
packer-init:
    packer init nixos-k3s.pkr.hcl

# Initialize Packer plugins for direct method
packer-init-direct:
    packer init nixos-k3s-direct.pkr.hcl
