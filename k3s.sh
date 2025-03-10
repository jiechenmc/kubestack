curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server --server https://10.0.0.60:6443 \
  --flannel-backend=none \
  --disable servicelb,traefik,local-storage \
  --disable-kube-proxy \
  --disable-network-policy \
  --disable-helm-controller \
  --cluster-init

kubectl create secret generic cloudflared-token-secret --from-literal=token=$CF_TOKEN   