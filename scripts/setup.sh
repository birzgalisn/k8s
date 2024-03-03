#!/bin/bash

set -e  # Exit on error

export DEBIAN_FRONTEND="noninteractive"
export ARCH="$(dpkg --print-architecture)"
export CONTAINERD_VERSION="1.7.13"
export RUNC_VERSION="1.1.12"
export CNI_VERSION="1.4.0"
export KUBERNETES_VERSION="1.29.2"
export KUBERNETES_MAJOR_MINOR_VERSION="$(echo $KUBERNETES_VERSION | cut -d '.' -f1,2)"

# Update the system
apt update
apt -y full-upgrade
[ -f /var/run/reboot-required ] && shutdown -r now

# Disable swap
sudo swapoff -a
sudo sed -i "/ swap / s/^\(.*\)$/#\1/g" /etc/fstab

# Disable ufw
systemctl stop ufw.service
systemctl disable ufw.service
iptables -F

# Load kernel modules required by kubernetes
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl settings for kubernetes networking
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.default.forwarding    = 1
EOF

sysctl --system

# Configure kubelet
mkdir -p /etc/systemd/system/kubelet.service.d
cat <<EOF | tee /etc/systemd/system/kubelet.service.d/20-hcloud.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external"
EOF

# Remove unofficial docker packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do apt-get remove $pkg; done

# Install containerd
curl -fsSL "https://github.com/containerd/containerd/releases/download/v$CONTAINERD_VERSION/containerd-$CONTAINERD_VERSION-linux-$ARCH.tar.gz" | tar -C /usr/local -zxvf -

mkdir -p /usr/local/lib/systemd/system
curl -fsSL "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service" -o /usr/local/lib/systemd/system/containerd.service

systemctl daemon-reload
systemctl enable --now containerd

# Install runc
curl -fsSL "https://github.com/opencontainers/runc/releases/download/v$RUNC_VERSION/runc.$ARCH" -o /tmp/runc
install -m 755 /tmp/runc /usr/local/sbin/runc
rm /tmp/runc

# Install cni
mkdir -p /opt/cni/bin
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/v$CNI_VERSION/cni-plugins-linux-$ARCH-v$CNI_VERSION.tgz" | tar -C /opt/cni/bin -zxvf -

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i -e "s/SystemdCgroup = false/SystemdCgroup = true/g" /etc/containerd/config.toml
systemctl restart containerd

# Install kubernetes
apt update
apt install -y apt-transport-https ca-certificates gpg
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_MAJOR_MINOR_VERSION/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_MAJOR_MINOR_VERSION/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
