crio_version: v1.36
k8s_version: v1.36
# primary control-plane node's own (static) address
k8s_api_ip: 10.144.138.245
# floating api endpoint held by kube-vip on whichever control-plane node leads (arp failover).
# keep it outside the router's dhcp range and the cilium lb pool (lb_ip_start..lb_ip_stop)
k8s_api_vip: 10.144.138.240
kube_vip_image: ghcr.io/kube-vip/kube-vip:v1.3.1
# control-plane nodes, matched against each node's ipv4 addresses (or minion id).
# the first one runs kubeadm init (it owns k8s_api_ip) and installs the cluster add-ons;
# the rest join as extra control-plane nodes. any node not listed joins as a worker.
k8s_masters:
  - 10.144.138.245
  - 10.144.138.249
  - 10.144.138.244
k8s_svc_port: 6443
cilium_version: 1.19.4
# virtctl cli, keep in step with kubernetes/infrastructure/kubevirt/kubevirt-operator.yaml
virtctl_version: v1.9.1
pod_cidr: 10.244.0.0/16
service_cidr: "10.96.0.0/12"
k8s_api_iface: enp4s0
k8s_api_prefix: 24
k8s_api_gateway: 10.144.138.1
k8s_api_dns: "10.144.138.1"
lb_ip_start: 10.144.138.200
lb_ip_stop: 10.144.138.220
hubble_metrics:
  - dns
  - drop
  - tcp
  - icmp
  - flow:sourceContext=reserved-identity;destinationContext=reserved-identity
  - port-distribution:destinationContext=reserved-identity
  - policy:sourceContext=reserved-identity;destinationContext=reserved-identity
# salt applies only this chart's prometheus-operator crds; argo cd installs the chart itself
kps_chart: /root/kubestack/kubernetes/helm/kube-prometheus-stack
# argo cd bootstrap; every other add-on is synced by argo from kubernetes/argocd/apps,
# not configured in this pillar
argocd_chart: /root/kubestack/kubernetes/helm/argo-cd
argocd_root_app: /root/kubestack/kubernetes/argocd/root.yaml
