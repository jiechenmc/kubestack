{% set home = salt['environ.get']('HOME') %}
{# api endpoint: the kube-vip vip when set, else the primary's own address #}
{% set api_endpoint = pillar.get('k8s_api_vip', pillar['k8s_api_ip']) %}
{# true when a cluster already exists for the current api endpoint #}
{% set cluster_matches_ip = "grep -qs 'server: https://" ~ api_endpoint ~ ":" ~ pillar['k8s_svc_port'] ~ "$' /etc/kubernetes/admin.conf" %}
{# true when this node's kubelet is already joined to the cluster at the api endpoint #}
{% set kubelet_matches_ip = "grep -qs 'server: https://" ~ api_endpoint ~ ":" ~ pillar['k8s_svc_port'] ~ "$' /etc/kubernetes/kubelet.conf" %}

{# node role: k8s_masters lists the control-plane nodes, anything not listed is a worker #}
{% set node_addrs = salt['grains.get']('ipv4', []) + [grains['id']] %}
{% set masters = pillar.get('k8s_masters', [pillar['k8s_api_ip']]) %}
{% set primary = masters[0] %}
{% set my_master_ips = masters | select('in', node_addrs) | list %}
{% set is_master = my_master_ips | length > 0 %}
{% set is_primary = primary in node_addrs %}
{% set crio_socket = 'unix:///var/run/crio/crio.sock' %}
{# joined = part of the cluster at the api endpoint. kubeadm points a control-plane node's kubelet.conf
   at its own local api server, so masters are checked via admin.conf; they must also run an api
   server, so a node joined as a worker gets re-joined as a master #}
{% if is_master %}
{% set node_joined = cluster_matches_ip ~ " && test -e /etc/kubernetes/manifests/kube-apiserver.yaml" %}
{% else %}
{% set node_joined = kubelet_matches_ip %}
{% endif %}
{% set my_ip = my_master_ips[0] if is_master else '' %}
{% set vip_iface = [] %}
{% for iface, addrs in salt['grains.get']('ip4_interfaces', {}).items() if my_ip in addrs %}
{% do vip_iface.append(iface) %}
{% endfor %}

disable_swap:
  cmd.run:
    - name: swapoff -a
    - onlyif: swapon --show | grep -q .

disable_swap_fstab:
  file.line:
    - name: /etc/fstab
    - match: '^\S+\s+\S+\s+swap\s+'
    - mode: delete
    - quiet: true

kubernetes_repo:
  file.managed:
    - name: /etc/yum.repos.d/kubernetes.repo
    - contents: |
        [kubernetes]
        name=Kubernetes
        baseurl=https://pkgs.k8s.io/core:/stable:/{{ pillar['k8s_version'] }}/rpm/
        enabled=1
        gpgcheck=1
        gpgkey=https://pkgs.k8s.io/core:/stable:/{{ pillar['k8s_version'] }}/rpm/repodata/repomd.xml.key
        exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
    - mode: "0644"
    - user: root
    - group: root


crio_repo:
  file.managed:
    - name: /etc/yum.repos.d/cri-o.repo
    - contents: |
        [cri-o]
        name=CRI-O
        baseurl=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/{{ pillar['crio_version'] }}/rpm/
        enabled=1
        gpgcheck=1
        gpgkey=https://download.opensuse.org/repositories/isv:/cri-o:/stable:/{{ pillar['crio_version'] }}/rpm/repodata/repomd.xml.key
    - mode: "0644"
    - user: root
    - group: root

install_container_selinux:
  pkg.installed:
    - name: container-selinux

install_kubernetes_and_crio:
  cmd.run:
    - name: dnf install -y cri-o kubelet kubeadm kubectl --disableexcludes=kubernetes
    - creates:
      - /usr/bin/kubelet
      - /usr/bin/kubeadm
      - /usr/bin/kubectl
      - /usr/bin/crio
    - require:
      - file: crio_repo
      - file: kubernetes_repo
      - pkg: install_container_selinux

crio_service:
  service.running:
    - name: crio
    - enable: True
    - require:
      - cmd: install_kubernetes_and_crio

kubectl_service:
  service.running:
    - name: kubelet
    - enable: True
    - require:
      - cmd: install_kubernetes_and_crio

firewall_pod_cidr:
  cmd.run:
    - name: firewall-cmd --permanent --zone=trusted --add-source={{ pillar['pod_cidr'] }}
    - onlyif: systemctl is-active --quiet firewalld
    - unless: firewall-cmd --zone=trusted --list-sources | grep -qF {{ pillar['pod_cidr'] }}

firewall_service_cidr:
  cmd.run:
    - name: firewall-cmd --permanent --zone=trusted --add-source={{ pillar['service_cidr'] }}
    - onlyif: systemctl is-active --quiet firewalld
    - unless: firewall-cmd --zone=trusted --list-sources | grep -qF {{ pillar['service_cidr'] }}

firewall_lan_to_pods:
  cmd.run:
    - name: |
        firewall-cmd --permanent --new-policy lan-to-pods
        firewall-cmd --permanent --policy lan-to-pods --add-ingress-zone public
        firewall-cmd --permanent --policy lan-to-pods --add-egress-zone ANY
        firewall-cmd --permanent --policy lan-to-pods --add-rich-rule 'rule family="ipv4" destination address="{{ pillar['pod_cidr'] }}" accept'
    - onlyif: systemctl is-active --quiet firewalld
    - unless: firewall-cmd --permanent --info-policy lan-to-pods

# kubelet, cilium health/hubble, nodeports on every node; api server, etcd, scheduler and
# controller-manager on control-plane nodes
{% set k8s_ports = ['10250/tcp', '4240/tcp', '4244/tcp', '30000-32767/tcp'] %}
{% if is_master %}
{% set k8s_ports = k8s_ports + [pillar['k8s_svc_port'] ~ '/tcp', '2379-2380/tcp', '10257/tcp', '10259/tcp'] %}
{% endif %}
firewall_k8s_ports:
  cmd.run:
    - name: |
{%- for port in k8s_ports %}
        firewall-cmd --permanent --zone=public --add-port={{ port }}
{%- endfor %}
    - onlyif: systemctl is-active --quiet firewalld
    - unless: >-
        ports="$(firewall-cmd --permanent --zone=public --list-ports)";
{%- for port in k8s_ports %}
        echo " $ports " | grep -qF " {{ port }} " &&
{%- endfor %}
        true

firewall_reload:
  cmd.run:
    - name: firewall-cmd --reload
    - onlyif: systemctl is-active --quiet firewalld
    - onchanges:
      - cmd: firewall_pod_cidr
      - cmd: firewall_service_cidr
      - cmd: firewall_lan_to_pods
      - cmd: firewall_k8s_ports

enable_br_netfilter:
  kmod.present:
    - name: br_netfilter

enable_ip_forward:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1

# desktop selinux-denial helper; its SetroubleshootPrivileged.py leaks memory without bound
# (14Gi after a week on a worker). denials still land in the audit log without it
remove_setroubleshoot:
  pkg.removed:
    - pkgs:
      - setroubleshoot-server
      - setroubleshoot-plugins

# hostPath for the otel-logs agent's filelog checkpoints. the collector runs as root, but selinux
# still only lets containers write container_file_t paths (a plain mkdir gets container_var_lib_t)
otelcol_storage_dir:
  file.directory:
    - name: /var/lib/otelcol
    - user: root
    - group: root
    - mode: "0755"
  cmd.run:
    - name: chcon -R -t container_file_t /var/lib/otelcol
    - unless: ls -dZ /var/lib/otelcol | grep -q container_file_t
    - require:
      - file: otelcol_storage_dir

add_autocomplete_to_zshrc:
  file.append:
    - name: {{ home }}/.zshrc
    - text: "source <(kubectl completion zsh)"

{% if is_master %}
kubeconfig_env:
  file.append:
    - name: /etc/profile.d/kubernetes.sh
    - text: 'export KUBECONFIG=/etc/kubernetes/admin.conf'

{% if pillar.get('k8s_api_vip') %}
# kube-vip static pod: the leader of the plndr-cp-lock lease holds k8s_api_vip on this lan (arp).
# it talks to this node's own api server (kubernetes_addr) so it never depends on the vip itself.
# the primary mounts super-admin.conf: during kubeadm init, admin.conf has no rbac yet and the
# init phases already need the vip; joined masters only have admin.conf
kube_vip:
  file.managed:
    - name: /etc/kubernetes/manifests/kube-vip.yaml
    - makedirs: True
    - contents: |
        apiVersion: v1
        kind: Pod
        metadata:
          name: kube-vip
          namespace: kube-system
        spec:
          hostNetwork: true
          containers:
            - name: kube-vip
              image: {{ pillar['kube_vip_image'] }}
              args: ["manager"]
              env:
                - {name: vip_arp, value: "true"}
                - {name: port, value: "{{ pillar['k8s_svc_port'] }}"}
                - {name: vip_interface, value: "{{ vip_iface | first | default('') }}"}
                - {name: vip_subnet, value: "32"}
                - {name: address, value: "{{ pillar['k8s_api_vip'] }}"}
                - {name: cp_enable, value: "true"}
                - {name: cp_namespace, value: kube-system}
                - {name: svc_enable, value: "false"} # cilium announces loadbalancer ips
                - {name: vip_leaderelection, value: "true"}
                - {name: vip_leasename, value: plndr-cp-lock}
                - {name: vip_leaseduration, value: "5"}
                - {name: vip_renewdeadline, value: "3"}
                - {name: vip_retryperiod, value: "1"}
                - {name: kubernetes_addr, value: "https://{{ my_ip }}:{{ pillar['k8s_svc_port'] }}"}
                - {name: prometheus_server, value: ":2112"}
              securityContext:
                capabilities:
                  add: ["NET_ADMIN", "NET_RAW"]
              volumeMounts:
                - name: kubeconfig
                  mountPath: /etc/kubernetes/admin.conf
                  readOnly: true
          volumes:
            - name: kubeconfig
              hostPath:
                path: /etc/kubernetes/{{ 'super-admin.conf' if is_primary else 'admin.conf' }}
                type: File
    - require:
{%- if is_primary %}
      - cmd: kubeadm_reset
{%- else %}
      - cmd: kubeadm_join
{%- endif %}

# right after a join the kubelet can register the new static pod without ever starting it
# (mirror pod stuck Pending, no sandbox); a restart makes it re-read its manifests cleanly.
# running static pods (etcd, api server) keep running across the restart
kube_vip_kubelet_restart:
  cmd.run:
    - name: systemctl restart kubelet
    - onchanges:
      - file: kube_vip

# control-plane nodes run workloads too (no dedicated workers)
control_plane_untaint:
  cmd.run:
    - name: kubectl taint node "$(kubectl get node -o name -l kubernetes.io/hostname="$(hostname)" | cut -d/ -f2)" node-role.kubernetes.io/control-plane:NoSchedule-
    - onlyif: kubectl get node -l kubernetes.io/hostname="$(hostname)" -o jsonpath='{.items[*].spec.taints}' | grep -q node-role.kubernetes.io/control-plane
    - require:
{%- if is_primary %}
      - cmd: kubeadm_init
{%- else %}
      - cmd: kubeadm_join
{%- endif %}
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf
{% endif %}
{% endif %}

{% if not is_primary %}
# secondary control-plane and worker nodes: join the cluster at k8s_api_ip.
# the join command comes from pillar k8s_join_command when set, e.g.
#   salt-call state.apply pillar='{"k8s_join_command": "kubeadm join ...", "k8s_certificate_key": "..."}'
# (from `kubeadm token create --print-join-command` and, for masters,
# `kubeadm init phase upload-certs --upload-certs` on the primary), otherwise they are
# fetched over ssh from the primary master, which needs root key access to it.
kubeadm_join_reset:
  cmd.run:
    - name: |
        kubeadm reset -f --cri-socket={{ crio_socket }}
        umount /var/run/cilium/cgroupv2 2>/dev/null || true
        rm -rf /etc/cni/net.d/* /var/lib/cni /var/run/cilium
        ip link delete cilium_host 2>/dev/null || true
        ip link delete cilium_vxlan 2>/dev/null || true
    # also catches a half-finished join (certs/manifests written, no kubelet.conf yet)
    - onlyif: test -e /etc/kubernetes/kubelet.conf -o -e /etc/kubernetes/pki/ca.crt
    - unless: {{ node_joined | yaml_encode }}
    - require:
      - service: crio_service

kubeadm_join:
  cmd.run:
    - name: |
        set -e
{%- if pillar.get('k8s_join_command') %}
        join_cmd={{ pillar['k8s_join_command'] | yaml_encode }}
{%- else %}
        join_cmd="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@{{ primary }} kubeadm token create --print-join-command)"
{%- endif %}
{%- if is_master %}
{%- if pillar.get('k8s_certificate_key') %}
        cert_key={{ pillar['k8s_certificate_key'] | yaml_encode }}
{%- else %}
        cert_key="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@{{ primary }} kubeadm init phase upload-certs --upload-certs | tail -1)"
{%- endif %}
        $join_cmd --cri-socket={{ crio_socket }} --control-plane --certificate-key "$cert_key" --apiserver-advertise-address={{ my_master_ips[0] }}
{%- else %}
        $join_cmd --cri-socket={{ crio_socket }}
{%- endif %}
    - unless: {{ node_joined | yaml_encode }}
    - require:
      - cmd: kubeadm_join_reset
      - service: kubectl_service
      - kmod: enable_br_netfilter
      - sysctl: enable_ip_forward
{% else %}
static_ip:
  cmd.run:
    - name: |
        nmcli con mod {{ pillar['k8s_api_iface'] }} \
          ipv4.method manual \
          ipv4.addresses {{ pillar['k8s_api_ip'] }}/{{ pillar['k8s_api_prefix'] }} \
          ipv4.gateway {{ pillar['k8s_api_gateway'] }} \
          ipv4.dns "{{ pillar['k8s_api_dns'] }}" \
          connection.autoconnect yes
        nmcli dev reapply {{ pillar['k8s_api_iface'] }}
    - unless: >-
        test "$(nmcli -g ipv4.method,ipv4.addresses con show {{ pillar['k8s_api_iface'] }} | paste -sd,)"
        = "manual,{{ pillar['k8s_api_ip'] }}/{{ pillar['k8s_api_prefix'] }}"

kubeadm_reset:
  cmd.run:
    - name: |
        kubeadm reset -f --cri-socket=unix:///var/run/crio/crio.sock
        umount /var/run/cilium/cgroupv2 2>/dev/null || true
        rm -rf /etc/cni/net.d/* /var/lib/cni /var/run/cilium
        ip link delete cilium_host 2>/dev/null || true
        ip link delete cilium_vxlan 2>/dev/null || true
    - unless: {{ cluster_matches_ip | yaml_encode }}
    - require:
      - service: crio_service
      - cmd: static_ip

kubeadm_init:
  cmd.run:
    - name: kubeadm init --cri-socket={{ crio_socket }} --skip-phases=addon/kube-proxy --apiserver-advertise-address={{ pillar['k8s_api_ip'] }} --control-plane-endpoint={{ api_endpoint }}:{{ pillar['k8s_svc_port'] }} --service-cidr={{ pillar['service_cidr'] }} --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests
    - unless: {{ cluster_matches_ip | yaml_encode }}
    - require:
      - cmd: kubeadm_reset
{%- if pillar.get('k8s_api_vip') %}
      - file: kube_vip
{%- endif %}
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# kubeadm refuses extra control-plane joins without a controlPlaneEndpoint; clusters
# initialized before --control-plane-endpoint was passed above lack one
kubeadm_control_plane_endpoint:
  cmd.run:
    - name: |
        kubectl -n kube-system get cm kubeadm-config -o yaml \
          | sed '/^  ClusterConfiguration: |$/a\    controlPlaneEndpoint: {{ api_endpoint }}:{{ pillar['k8s_svc_port'] }}' \
          | kubectl replace -f -
    - unless: kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep -q '^controlPlaneEndpoint:'
    - require:
      - cmd: kubeadm_init
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

add_cilium_repo:
  cmd.run:
    - name: helm repo add cilium https://helm.cilium.io/ && helm repo update
    - unless: helm repo list | grep cilium

# MTU=1500: otherwise cilium uses the smallest host device mtu (tailscale0: 1280), leaving pods at 1230,
# too small for quic's 1280-byte packets (cloudflared quic handshakes timed out)
# routingMode=native: no vxlan encapsulation (pods get the full 1500 mtu instead of 1450); pod cidr is
# routed directly, autoDirectNodeRoutes adds node-to-node pod routes once more nodes share this lan
install_cilium:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 cilium cilium/cilium \
          --version {{ pillar['cilium_version'] }} \
          --namespace kube-system \
          --set kubeProxyReplacement=true \
          --set MTU=1500 \
          --set routingMode=native \
          --set ipv4NativeRoutingCIDR={{ pillar['pod_cidr'] }} \
          --set autoDirectNodeRoutes=true \
          --set k8sServiceHost={{ api_endpoint }} \
          --set k8sServicePort={{ pillar['k8s_svc_port'] }} \
          --set operator.replicas=1 \
          --set ipam.mode=cluster-pool \
          --set ipam.operator.clusterPoolIPv4PodCIDRList={{ pillar['pod_cidr'] }} \
          --set ipam.operator.clusterPoolIPv4MaskSize=24 \
          --set hubble.relay.enabled=true \
          --set hubble.ui.enabled=true \
          --set hubble.ui.service.type=LoadBalancer \
          --set hubble.ui.ingress.enabled=true \
          --set hubble.ui.ingress.className=traefik \
          --set-json 'hubble.ui.ingress.hosts=["hubble.home.arpa"]' \
          --set socketLB.hostNamespaceOnly=false \
          --set l2announcements.enabled=true \
          --set externalIPs.enabled=true \
          --set k8sClientRateLimit.qps=20 \
          --set k8sClientRateLimit.burst=40 \
          --set rollOutCiliumPods=true \
          --set operator.rollOutPods=true \
          --set prometheus.enabled=true \
          --set prometheus.serviceMonitor.enabled=true \
          --set operator.prometheus.enabled=true \
          --set operator.prometheus.serviceMonitor.enabled=true \
          --set hubble.metrics.serviceMonitor.enabled=true \
          --set envoy.prometheus.serviceMonitor.enabled=true \
          --set hubble.metrics.enableOpenMetrics=true \
          --set-json 'hubble.metrics.enabled={{ pillar['hubble_metrics'] | tojson }}' \
          --set dashboards.enabled=true \
          --set hubble.metrics.dashboards.enabled=true \
          --set operator.dashboards.enabled=true
    - require:
      - cmd: add_cilium_repo
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf
cilium_l2_announcements:
  cmd.run:
    - name: |
        kubectl apply -f - <<'MANIFEST'
        apiVersion: cilium.io/v2
        kind: CiliumLoadBalancerIPPool
        metadata:
          name: lan
        spec:
          blocks:
            - start: {{ pillar['lb_ip_start'] }}
              stop: {{ pillar['lb_ip_stop'] }}
        ---
        apiVersion: cilium.io/v2alpha1
        kind: CiliumL2AnnouncementPolicy
        metadata:
          name: lan
        spec:
          # any wired nic: nodes differ (enp4s0, eno2); excludes wifi (wlp3s0 on the primary)
          interfaces:
            - ^en
          loadBalancerIPs: true
          externalIPs: true
        MANIFEST
    - require:
      - cmd: install_cilium
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# prometheus-operator, prometheus, alertmanager, grafana, node-exporter, kube-state-metrics.
# installed before cilium/rook/cnpg monitors so their ServiceMonitor/PodMonitor CRDs exist
kube_prometheus_stack:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 kube-prometheus-stack {{ pillar['kps_chart'] }} \
          --namespace monitoring --create-namespace \
          --values {{ pillar['kps_chart'] }}/values-kubestack.yaml
    - require:
      - cmd: kubeadm_init
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# metrics.k8s.io api (kubectl top, hpa)
metrics_server:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 metrics-server {{ pillar['metrics_server_chart'] }} \
          --namespace kube-system \
          --values {{ pillar['metrics_server_chart'] }}/values-kubestack.yaml
    - require:
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# argo cd: syncs every add-on in kubernetes/argocd/apps from git (ceph so far). salt only bootstraps
# argo cd itself and the root app; change those add-ons in git, not here
argocd:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 argocd {{ pillar['argocd_chart'] }} \
          --namespace argocd --create-namespace \
          --values {{ pillar['argocd_chart'] }}/values-kubestack.yaml
        kubectl wait --for condition=established --timeout=120s crd/applications.argoproj.io
        kubectl apply -f {{ pillar['argocd_root_app'] }}
    - require:
      - cmd: install_cilium
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# cortex/tempo/loki need the rgw bucket storage class from the ceph-cluster app; argo syncs it
# asynchronously, so wait for it here (returns immediately once ceph is up)
ceph_ready:
  cmd.run:
    - name: |
        until kubectl get storageclass rook-ceph-bucket >/dev/null 2>&1; do sleep 10; done
        kubectl -n rook-ceph wait --for=jsonpath='{.status.phase}'=Ready --timeout=900s cephobjectstore/objectstore
    - timeout: 1800
    - require:
      - cmd: argocd
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# cloudnative-pg operator: manages postgres Cluster resources
cnpg_operator:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 cnpg {{ pillar['cnpg_chart'] }} \
          --namespace cnpg-system --create-namespace \
          --values {{ pillar['cnpg_chart'] }}/values.yaml \
          --set monitoring.podMonitorEnabled=true \
          --set monitoring.grafanaDashboard.create=true
    - require:
      - cmd: install_cilium
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# cortex: long-term prometheus storage (remote write), blocks in a ceph rgw bucket
cortex:
  cmd.run:
    - name: |
        kubectl create namespace cortex --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -f - <<'MANIFEST'
        apiVersion: objectbucket.io/v1alpha1
        kind: ObjectBucketClaim
        metadata:
          name: cortex-bucket
          namespace: cortex
        spec:
          bucketName: cortex
          storageClassName: rook-ceph-bucket
        MANIFEST
        kubectl -n cortex wait --for=jsonpath='{.status.phase}'=Bound obc/cortex-bucket --timeout=120s
        helm upgrade --install --history-max 3 cortex {{ pillar['cortex_chart'] }} \
          --namespace cortex \
          --values {{ pillar['cortex_chart'] }}/values-kubestack.yaml
    - require:
      - cmd: ceph_ready
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# tracing: tempo (traces in a ceph rgw bucket) behind an otlp gateway collector
tracing:
  cmd.run:
    - name: |
        kubectl create namespace tracing --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -f - <<'MANIFEST'
        apiVersion: objectbucket.io/v1alpha1
        kind: ObjectBucketClaim
        metadata:
          name: tempo-bucket
          namespace: tracing
        spec:
          bucketName: tempo
          storageClassName: rook-ceph-bucket
        MANIFEST
        kubectl -n tracing wait --for=jsonpath='{.status.phase}'=Bound obc/tempo-bucket --timeout=120s
        helm upgrade --install --history-max 3 tempo {{ pillar['tempo_chart'] }} \
          --namespace tracing \
          --values {{ pillar['tempo_chart'] }}/values-kubestack.yaml
        helm upgrade --install --history-max 3 otel-collector {{ pillar['otelcol_chart'] }} \
          --namespace tracing \
          --values {{ pillar['otelcol_chart'] }}/values-kubestack.yaml
    - require:
      - cmd: ceph_ready
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# logging: loki (chunks in a ceph rgw bucket) fed by an otel collector daemonset tailing pod logs
logging:
  cmd.run:
    - name: |
        kubectl create namespace logging --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -f - <<'MANIFEST'
        apiVersion: objectbucket.io/v1alpha1
        kind: ObjectBucketClaim
        metadata:
          name: loki-bucket
          namespace: logging
        spec:
          bucketName: loki
          storageClassName: rook-ceph-bucket
        MANIFEST
        kubectl -n logging wait --for=jsonpath='{.status.phase}'=Bound obc/loki-bucket --timeout=120s
        helm upgrade --install --history-max 3 loki {{ pillar['loki_chart'] }} \
          --namespace logging \
          --values {{ pillar['loki_chart'] }}/values-kubestack.yaml
        helm upgrade --install --history-max 3 otel-logs {{ pillar['otelcol_chart'] }} \
          --namespace logging \
          --values {{ pillar['otelcol_chart'] }}/values-logs.yaml
    - require:
      - cmd: ceph_ready
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# infisical secrets-operator: InfisicalSecret resources -> kubernetes Secrets
infisical_operator:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 infisical-operator {{ pillar['infisical_operator_chart'] }} \
          --namespace infisical-operator-system --create-namespace \
          --values {{ pillar['infisical_operator_chart'] }}/values-kubestack.yaml
        kubectl apply -f - <<'MANIFEST'
        # let prometheus scrape the operator's authenticated /metrics endpoint
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: infisical-operator-metrics-reader-prometheus
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: infisical-opera-metrics-reader
        subjects:
          - kind: ServiceAccount
            name: kube-prometheus-stack-prometheus
            namespace: monitoring
        MANIFEST
    - require:
      - cmd: kube_prometheus_stack
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

# self-hosted github actions runners (actions-runner-controller) for
# jiechenmc/trix: PR previews (trix-cluster) and production deploys
# (trix-deploy); and jiechenmc/plantain's unity builds (plantain-build).
# their permissions and github token (synced from infisical,
# hence the require) are in the manifest.
github_runners:
  cmd.run:
    - name: |
        helm upgrade --install --history-max 3 arc {{ pillar['arc_controller_chart'] }} \
          --namespace arc-systems --create-namespace \
          --values {{ pillar['arc_controller_chart'] }}/values-kubestack.yaml
        kubectl apply -f {{ pillar['github_runners_manifest'] }}
        helm upgrade --install --history-max 3 trix-cluster {{ pillar['arc_scale_set_chart'] }} \
          --namespace arc-runners \
          --values {{ pillar['arc_scale_set_chart'] }}/values-trix-cluster.yaml
        helm upgrade --install --history-max 3 trix-deploy {{ pillar['arc_scale_set_chart'] }} \
          --namespace arc-runners \
          --values {{ pillar['arc_scale_set_chart'] }}/values-trix-deploy.yaml
        helm upgrade --install --history-max 3 plantain-build {{ pillar['arc_scale_set_chart'] }} \
          --namespace arc-runners \
          --values {{ pillar['arc_scale_set_chart'] }}/values-plantain-build.yaml
    - require:
      - cmd: infisical_operator
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf
{% endif %}
