#!/bin/sh

# On master node:
# Initialize the Kubernetes cluster
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=0.0.0.0 \
  --upload-certs \
  --control-plane-endpoint=10.255.0.2

# Configure kubectl for the current user
mkdir -p $HOME/.kube && \
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && \
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Export KUBECONFIG environment variable
export KUBECONFIG=/etc/kubernetes/admin.conf

# Apply Flannel CNI (Container Network Interface) plugin
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml


# On each worker node:
# Get join command and token from master
JOIN_COMMAND=$(kubeadm token create --print-join-command)

# Output join command for worker nodes
echo "Run the following command on each worker node to join the cluster:"
echo "$JOIN_COMMAND"
