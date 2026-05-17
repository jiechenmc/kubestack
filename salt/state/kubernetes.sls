{% set home = salt['environ.get']('HOME') %}

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

firewall_reload:
  cmd.run:
    - name: firewall-cmd --reload
    - onchanges:
      - cmd: firewall_pod_cidr
      - cmd: firewall_service_cidr

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

kubeadm_init:
  cmd.run:
    - name: kubeadm init --skip-phases=addon/kube-proxy --apiserver-advertise-address={{ pillar['k8s_api_ip'] }} --service-cidr={{ pillar['service_cidr'] }}
    - unless: kubectl cluster-info --request-timeout=5s
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
          --set socketLB.hostNamespaceOnly=false
    - unless: helm status cilium -n kube-system
    - require:
      - cmd: add_cilium_repo
    - env:
      - KUBECONFIG: /etc/kubernetes/admin.conf