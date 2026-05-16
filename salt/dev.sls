{% set user = salt['grains.get']('username') %}
{% set home = salt['environ.get']('HOME') %}

install_development_tools:
  pkg.group_installed:
    - name: Development Tools

install_zsh:
  pkg.installed:
    - name: zsh

install_oh_my_zsh:
  cmd.run:
    - name: 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    - unless: test -d {{ home }}/.oh-my-zsh
    - runas: {{ user }}

set_default_shell_zsh:
  user.present:
    - name: {{ user }}
    - shell: /usr/bin/zsh

add_homebrew_to_zshrc:
  file.append:
    - name: {{ home }}/.zshrc
    - text: 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'