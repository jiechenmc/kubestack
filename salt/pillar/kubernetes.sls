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
cnpg_chart: /root/kubestack/kubernetes/helm/cloudnative-pg
kps_chart: /root/kubestack/kubernetes/helm/kube-prometheus-stack
cortex_chart: /root/kubestack/kubernetes/helm/cortex
tempo_chart: /root/kubestack/kubernetes/helm/tempo
otelcol_chart: /root/kubestack/kubernetes/helm/opentelemetry-collector
loki_chart: /root/kubestack/kubernetes/helm/loki
metrics_server_chart: /root/kubestack/kubernetes/helm/metrics-server
infisical_operator_chart: /root/kubestack/kubernetes/helm/secrets-operator
arc_controller_chart: /root/kubestack/kubernetes/helm/gha-runner-scale-set-controller
arc_scale_set_chart: /root/kubestack/kubernetes/helm/gha-runner-scale-set
github_runners_manifest: /root/kubestack/kubernetes/manifests/github-runners.yaml
# argo cd bootstrap; ceph (rook, csi drivers, snapshot-controller, cluster) is synced by argo from
# kubernetes/argocd/apps and kubernetes/infrastructure/ceph, not configured in this pillar
argocd_chart: /root/kubestack/kubernetes/helm/argo-cd
argocd_root_app: /root/kubestack/kubernetes/argocd/root.yaml
