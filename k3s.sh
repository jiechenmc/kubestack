# On extra
# curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server --server https://10.0.0.60:6443 \
#   --flannel-backend=none \
#   --disable-kube-proxy \
#   --disable servicelb \
#   --disable-network-policy \
#   --disable traefik \
#   --cluster-init

kubectl create secret generic cloudflared-token-secret --from-literal=token=$CF_TOKEN