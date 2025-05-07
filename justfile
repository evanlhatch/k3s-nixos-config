# NixOS K3s Cluster on Hetzner Cloud Justfile

# Default recipe to show help
default:
    @just --list

# Create Hetzner Cloud network
create-hetzner-network:
    hcloud network create --name ${PRIVATE_NETWORK_NAME:-k3s-net} --ip-range 10.0.0.0/16
    hcloud network add-subnet ${PRIVATE_NETWORK_NAME:-k3s-net} --network-zone ${HETZNER_NETWORK_ZONE:-us-east} --type server --ip-range 10.0.0.0/16

# Create Hetzner Cloud firewall
create-hetzner-firewall:
    hcloud firewall create --name ${FIREWALL_NAME:-k3s-fw}
    # Base Rules
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 22 --source-ips ${ADMIN_PUBLIC_IP}/32 --description "SSH from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips ${ADMIN_PUBLIC_IP}/32 --description "ICMP from Admin"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol icmp --source-ips 10.0.0.0/16 --description "ICMP from Private Net"
    # K3s Core Rules
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 6443 --source-ips 10.0.0.0/16,${ADMIN_PUBLIC_IP}/32 --description "K3s API"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 10250 --source-ips 10.0.0.0/16 --description "Kubelet"
    # K3s HA Etcd Rules (Add now for future readiness)
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 2379 --source-ips 10.0.0.0/16 --description "Etcd Client"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 2380 --source-ips 10.0.0.0/16 --description "Etcd Peer"
    # Tailscale Rules
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol udp --port 41641 --source-ips 0.0.0.0/0 --description "Tailscale"
    # Ingress Rules (Allow from ANY initially, restrict later if needed)
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 80 --source-ips 0.0.0.0/0 --description "Traefik HTTP"
    hcloud firewall add-rule ${FIREWALL_NAME:-k3s-fw} --direction in --protocol tcp --port 443 --source-ips 0.0.0.0/0 --description "Traefik HTTPS"

# Create Hetzner Cloud placement group
create-hetzner-placement-group:
    hcloud placement-group create --name ${PLACEMENT_GROUP_NAME:-k3s-placement-group} --type spread

# Create Hetzner Cloud SSH key
create-hetzner-ssh-key:
    hcloud ssh-key create --name "${HETZNER_SSH_KEY_NAME:-k3s-ssh-key}" --public-key-from-file ~/.ssh/id_ed25519.pub

# Create Hetzner Cloud control plane node using nixos-anywhere
create-control-node:
    hcloud server create \
        --name hetzner-control-01 \
        --type ${CONTROL_PLANE_VM_TYPE:-cpx31} \
        --image debian-12 \
        --ssh-key ${HETZNER_SSH_KEY_NAME:-k3s-ssh-key} \
        --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
        --firewall ${FIREWALL_NAME:-k3s-fw} \
        --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
        --location ${HETZNER_LOCATION:-ash} \
        --label ${CLUSTER_IDENTIFIER:-k8s-cluster=k3s-us-east} \
        --label ${CONTROL_PLANE_POOL:-k8s-nodepool=control-plane}
    nixos-anywhere --flake .#hetzner-control-01 root@hetzner-control-01

# Create Hetzner Cloud worker node using nixos-anywhere
create-worker-node:
    hcloud server create \
        --name hetzner-worker-static-01 \
        --type ${WORKER_VM_TYPE:-cpx21} \
        --image debian-12 \
        --ssh-key ${HETZNER_SSH_KEY_NAME:-k3s-ssh-key} \
        --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
        --firewall ${FIREWALL_NAME:-k3s-fw} \
        --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
        --location ${HETZNER_LOCATION:-ash} \
        --label ${CLUSTER_IDENTIFIER:-k8s-cluster=k3s-us-east} \
        --label ${STATIC_WORKER_POOL:-k8s-nodepool=static-workers}
    nixos-anywhere --flake .#hetzner-worker-static-01 root@hetzner-worker-static-01

# Deploy the NixOS configuration to the control plane node
deploy-control-node:
    deploy --skip-checks --targets hetzner-control-01

# Deploy the NixOS configuration to the worker node
deploy-worker-node:
    deploy --skip-checks --targets hetzner-worker-static-01

# Get the kubeconfig from the control plane node
get-kubeconfig:
    #!/usr/bin/env bash
    mkdir -p ~/.kube
    CONTROL_IP=$(tailscale ip hetzner-control-01)
    ssh ${ADMIN_USERNAME:-nixos}@$CONTROL_IP "sudo cat /etc/rancher/k3s/k3s.yaml" | \
      sed "s/127.0.0.1/$CONTROL_IP/g" > ~/.kube/config.k3s
    chmod 600 ~/.kube/config.k3s
    echo "Kubeconfig saved to ~/.kube/config.k3s"
    echo "Use it with: export KUBECONFIG=~/.kube/config.k3s"

# Install Flux CD
install-flux:
    flux bootstrap github \
        --owner=${GITHUB_USER:-evanlhatch} \
        --repository=${FLUX_REPO:-kube-flux} \
        --branch=main \
        --path=./clusters/k3s-us-east \
        --personal

# Build the control plane image
build-control-image:
    nix build .#control-plane-disk-image
    echo "Control plane disk image built at ./result"

# Build the worker image
build-worker-image:
    nix build .#worker-disk-image
    echo "Worker disk image built at ./result"

# Compress and register the control plane image with Hetzner Cloud
register-control-image: build-control-image
    @echo "Compressing control plane image..."
    @cp ./result/nixos.qcow2 ./k3s-control-image.qcow2
    @qemu-img convert -c -O qcow2 ./k3s-control-image.qcow2 ./k3s-control-image-compressed.qcow2
    @echo "Registering control plane image with Hetzner Cloud..."
    @IMAGE_NAME="k3s-control-$(date +%Y%m%d-%H%M%S)"
    @hcloud image create --name $IMAGE_NAME --description "K3s Control Plane Node with Tailscale CNI and Infisical Agent" --type snapshot --file ./k3s-control-image-compressed.qcow2
    @echo "Image registered as $IMAGE_NAME"
    @echo "Use this image name in the create-control-node-from-image command"
    @echo "Cleaning up temporary files..."
    @rm ./k3s-control-image.qcow2 ./k3s-control-image-compressed.qcow2

# Compress and register the worker image with Hetzner Cloud
register-worker-image: build-worker-image
    @echo "Compressing worker image..."
    @cp ./result/nixos.qcow2 ./k3s-worker-image.qcow2
    @qemu-img convert -c -O qcow2 ./k3s-worker-image.qcow2 ./k3s-worker-image-compressed.qcow2
    @echo "Registering worker image with Hetzner Cloud..."
    @IMAGE_NAME="k3s-worker-$(date +%Y%m%d-%H%M%S)"
    @hcloud image create --name $IMAGE_NAME --description "K3s Worker Node with Tailscale CNI and Infisical Agent" --type snapshot --file ./k3s-worker-image-compressed.qcow2
    @echo "Image registered as $IMAGE_NAME"
    @echo "Use this image name in the create-worker-node-from-image command"
    @echo "Cleaning up temporary files..."
    @rm ./k3s-worker-image.qcow2 ./k3s-worker-image-compressed.qcow2

# Create Hetzner Cloud control plane node using custom image
create-control-node-from-image:
    @read -p "Enter the control plane image name: " IMAGE_NAME && \
    hcloud server create \
        --name hetzner-control-01 \
        --type ${CONTROL_PLANE_VM_TYPE:-cpx31} \
        --image $$IMAGE_NAME \
        --ssh-key ${HETZNER_SSH_KEY_NAME:-k3s-ssh-key} \
        --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
        --firewall ${FIREWALL_NAME:-k3s-fw} \
        --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
        --location ${HETZNER_LOCATION:-ash} \
        --label ${CLUSTER_IDENTIFIER:-k8s-cluster=k3s-us-east} \
        --label ${CONTROL_PLANE_POOL:-k8s-nodepool=control-plane}

# Create Hetzner Cloud worker node using custom image
create-worker-node-from-image:
    @read -p "Enter the worker image name: " IMAGE_NAME && \
    hcloud server create \
        --name hetzner-worker-static-01 \
        --type ${WORKER_VM_TYPE:-cpx21} \
        --image $$IMAGE_NAME \
        --ssh-key ${HETZNER_SSH_KEY_NAME:-k3s-ssh-key} \
        --network ${PRIVATE_NETWORK_NAME:-k3s-net} \
        --firewall ${FIREWALL_NAME:-k3s-fw} \
        --placement-group ${PLACEMENT_GROUP_NAME:-k3s-placement-group} \
        --location ${HETZNER_LOCATION:-ash} \
        --label ${CLUSTER_IDENTIFIER:-k8s-cluster=k3s-us-east} \
        --label ${STATIC_WORKER_POOL:-k8s-nodepool=static-workers}
