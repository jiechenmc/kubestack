{% set home = salt['environ.get']('HOME') %}
{# true when a cluster already exists for the current k8s_api_ip #}
{% set cluster_matches_ip = "grep -qs 'server: https://" ~ pillar['k8s_api_ip'] ~ ":" ~ pillar['k8s_svc_port'] ~ "$' /etc/kubernetes/admin.conf" %}

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
    - unless: firewall-cmd --zone=trusted --list-sources | grep {{ pillar['pod_cidr'] }}

firewall_service_cidr:
  cmd.run:
    - name: firewall-cmd --permanent --zone=trusted --add-source={{ pillar['service_cidr'] }}
    - unless: firewall-cmd --zone=trusted --list-sources | grep {{ pillar['service_cidr'] }}

firewall_lan_to_pods:
  cmd.run:
    - name: |
        firewall-cmd --permanent --new-policy lan-to-pods
        firewall-cmd --permanent --policy lan-to-pods --add-ingress-zone public
        firewall-cmd --permanent --policy lan-to-pods --add-egress-zone ANY
        firewall-cmd --permanent --policy lan-to-pods --add-rich-rule 'rule family="ipv4" destination address="{{ pillar['pod_cidr'] }}" accept'
    - unless: firewall-cmd --permanent --info-policy lan-to-pods

firewall_reload:
  cmd.run:
    - name: firewall-cmd --reload
    - onchanges:
      - cmd: firewall_pod_cidr
      - cmd: firewall_service_cidr
      - cmd: firewall_lan_to_pods

enable_br_netfilter:
  kmod.present:
    - name: br_netfilter

enable_ip_forward:
  sysctl.present:
    - name: net.ipv4.ip_forward
    - value: 1

kubeconfig_env:
  file.append:
    - name: /etc/profile.d/kubernetes.sh
    - text: 'export KUBECONFIG=/etc/kubernetes/admin.conf'

add_autocomplete_to_zshrc:
  file.append:
    - name: {{ home }}/.zshrc
    - text: "source <(kubectl completion zsh)"

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
        rm -rf /etc/cni/net.d/* /var/lib/cni /var/run/cilium
        ip link delete cilium_host 2>/dev/null || true
        ip link delete cilium_vxlan 2>/dev/null || true
    - unless: {{ cluster_matches_ip | yaml_encode }}
    - require:
      - service: crio_service
      - cmd: static_ip

kubeadm_init:
  cmd.run:
    - name: kubeadm init --cri-socket=unix:///var/run/crio/crio.sock --skip-phases=addon/kube-proxy --apiserver-advertise-address={{ pillar['k8s_api_ip'] }} --service-cidr={{ pillar['service_cidr'] }}
    - unless: {{ cluster_matches_ip | yaml_encode }}
    - require:
      - cmd: kubeadm_reset
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf

add_cilium_repo:
  cmd.run:
    - name: helm repo add cilium https://helm.cilium.io/ && helm repo update
    - unless: helm repo list | grep cilium

install_cilium:
  cmd.run:
    - name: |
        helm upgrade --install cilium cilium/cilium \
          --version {{ pillar['cilium_version'] }} \
          --namespace kube-system \
          --set kubeProxyReplacement=true \
          --set k8sServiceHost={{ pillar['k8s_api_ip'] }} \
          --set k8sServicePort={{ pillar['k8s_svc_port'] }} \
          --set operator.replicas=1 \
          --set ipam.mode=cluster-pool \
          --set ipam.operator.clusterPoolIPv4PodCIDRList={{ pillar['pod_cidr'] }} \
          --set ipam.operator.clusterPoolIPv4MaskSize=24 \
          --set hubble.relay.enabled=true \
          --set hubble.ui.enabled=true \
          --set hubble.ui.service.type=LoadBalancer \
          --set socketLB.hostNamespaceOnly=false \
          --set l2announcements.enabled=true \
          --set externalIPs.enabled=true \
          --set k8sClientRateLimit.qps=20 \
          --set k8sClientRateLimit.burst=40 \
          --set rollOutCiliumPods=true \
          --set operator.rollOutPods=true \
          --set prometheus.enabled=true \
          --set operator.prometheus.enabled=true \
          --set hubble.metrics.enableOpenMetrics=true \
          --set-json 'hubble.metrics.enabled={{ pillar['hubble_metrics'] | tojson }}' \
          --set dashboards.enabled=true \
          --set hubble.metrics.dashboards.enabled=true \
          --set operator.dashboards.enabled=true
    - require:
      - cmd: add_cilium_repo
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
          interfaces:
            - ^{{ pillar['k8s_api_iface'] }}$
          loadBalancerIPs: true
          externalIPs: true
        MANIFEST
    - require:
      - cmd: install_cilium
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf
