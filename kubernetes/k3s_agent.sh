SERVER_IP=...

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server --server https://$SERVER_IP:6443 \
  --flannel-backend none \
  --disable-network-policy \
  --disable-helm-controller \
  --write-kubeconfig-mode 644 \
  --cluster-init