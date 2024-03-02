#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

# Update the system
sudo apt update

# Install Docker
sudo apt install -y docker.io

# Enable and start Docker service
sudo systemctl enable --now docker && sudo systemctl status docker | grep -q "active (running)" || sudo systemctl start docker

# Add Google Cloud apt key and Kubernetes repository
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/kubernetes.gpg] http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list

# Update package list
sudo apt update

# Install Kubernetes tools
sudo apt install -y kubeadm kubelet kubectl

# Hold Kubernetes packages to prevent automatic updates
sudo apt-mark hold kubeadm kubelet kubectl

# Disable swap
sudo swapoff -a && sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules required by Kubernetes
cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF

sudo modprobe overlay && sudo modprobe br_netfilter

# Configure sysctl settings for Kubernetes networking
cat > /etc/sysctl.d/10-kubernetes.conf << EOF
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
EOF

sudo sysctl --system

# Configure kubelet to use cgroupfs
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS="--cgroup-driver=cgroupfs"
EOF

# Restart kubelet service
sudo systemctl daemon-reload && sudo systemctl restart kubelet

# Configure Docker daemon
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

# Restart Docker service
sudo systemctl daemon-reload && sudo systemctl restart docker
