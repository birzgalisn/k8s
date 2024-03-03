#!/bin/sh

export DEBIAN_FRONTEND="noninteractive"

# Disable UFW
sudo systemctl stop ufw.service
sudo systemctl disable ufw.service
sudo iptables -F

# Load kernel modules required by Kubernetes
test -e /etc/modules-load.d/k8s.conf || cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl settings for Kubernetes networking
test -e /etc/sysctl.d/k8s.conf || cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Update the system
sudo apt update

# Install required packages
sudo apt install -y apt-transport-https ca-certificates curl gnupg

# Configure Containerd
sudo test -d /etc/containerd || sudo mkdir -p /etc/containerd
sudo test -e /etc/containerd/config.toml || sudo cat > /etc/containerd/config.toml <<EOF
disabled_plugins = ["cri"]

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF

# Configure Docker daemon
test -d /etc/docker || sudo mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Remove unofficial Docker packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done

# Add Docker's official GPG key
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add Docker repository to apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update

# Install Docker
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Prepare Docker
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# Disable swap
sudo swapoff -a
sudo sed -i "/ swap / s/^\(.*\)$/#\1/g" /etc/fstab

# Configure Kubelet
test -d /etc/systemd/system/kubelet.service.d || sudo mkdir -p /etc/systemd/system/kubelet.service.d
test -e /etc/systemd/system/kubelet.service.d/20-hcloud.conf || sudo cat > /etc/systemd/system/kubelet.service.d/20-hcloud.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external"
EOF

# Add Google Cloud's official GPG key
sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg -o /etc/apt/keyrings/googlecloud.asc
sudo chmod a+r /etc/apt/keyrings/googlecloud.asc

# Add the Kubernetes repository to apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/googlecloud.asc] https://apt.kubernetes.io kubernetes-xenial main" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt update

# Install Kubernetes
sudo apt install -y kubeadm kubelet kubectl

# Hold Kubernetes packages to prevent automatic updates
sudo apt-mark hold kubeadm kubelet kubectl

# Prepare Kubernetes
sudo systemctl enable kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
