curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server \
  --disable local-storage \
  --disable-helm-controller \
  --write-kubeconfig-mode 644 \
  --cluster-init



curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server --server https://10.10.0.1:6443 \
  --disable local-storage \
  --disable-helm-controller \
  --write-kubeconfig-mode 644 \
  --cluster-init

# kubectl create secret generic cloudflared-token-secret --from-literal=token=$CF_TOKEN   

# sudo apt-get install open-iscsi is needed for longhorn

#cilium install \         
  # --set k8sServiceHost=10.0.0.60 \
  # --set k8sServicePort=6443 \
  # --set kubeProxyReplacement=true \
  # --set=ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16"