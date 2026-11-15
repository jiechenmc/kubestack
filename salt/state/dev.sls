{% set user = salt['grains.get']('username') %}
{% set home = salt['environ.get']('HOME') %}

install_development_tools:
  pkg.group_installed:
    - name: Development Tools

install_zsh:
  pkg.installed:
    - name: zsh

download_helm_installer:
  cmd.run:
    - name: |
        curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
        chmod 700 /tmp/get_helm.sh
    - creates: /usr/local/bin/helm

run_helm_installer:
  cmd.run:
    - name: /tmp/get_helm.sh
    - creates: /usr/local/bin/helm
    - require:
      - cmd: download_helm_installer

# kubevirt cli (vm consoles, start/stop, image-upload). reinstalls when virtctl_version changes
install_virtctl:
  cmd.run:
    - name: |
        curl -fsSL -o /usr/local/bin/virtctl https://github.com/kubevirt/kubevirt/releases/download/{{ pillar['virtctl_version'] }}/virtctl-{{ pillar['virtctl_version'] }}-linux-amd64
        chmod 755 /usr/local/bin/virtctl
    - unless: /usr/local/bin/virtctl version --client 2>/dev/null | grep -q 'GitVersion:"{{ pillar['virtctl_version'] }}"'

install_oh_my_zsh:
  cmd.run:
    - name: 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    - unless: test -d {{ home }}/.oh-my-zsh
    - runas: {{ user }}

set_default_shell_zsh:
  user.present:
    - name: {{ user }}
    - shell: /usr/bin/zsh

add_kubectl_alias:
  file.append:
    - name: {{ home }}/.zshrc
    - text: "alias k=kubectl"