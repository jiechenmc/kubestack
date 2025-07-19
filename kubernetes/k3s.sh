export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
export SERVER_IP="$(ip route get 1.1.1.1 | awk '{print $7}')"

curl -sfL https://get.k3s.io | K3S_TOKEN=SECRET sh -s - server \
  --flannel-backend none \
  --disable-network-policy \
  --disable-helm-controller \
  --write-kubeconfig-mode 644 \
  --cluster-init

cilium install \
  --set k8sServiceHost=$SERVER_IP \
  --set k8sServicePort=6443 \
  --set kubeProxyReplacement=true \
  --set=ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16"