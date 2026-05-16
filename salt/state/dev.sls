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