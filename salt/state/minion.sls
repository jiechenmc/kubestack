# run the highstate whenever the minion starts (i.e. on boot), so a rebooted node converges
# without a manual `salt '*' state.apply`
minion_startup_highstate:
  file.managed:
    - name: /etc/salt/minion.d/startup.conf
    - contents: |
        startup_states: highstate
    - mode: "0644"
    - user: root
    - group: root

salt_minion_service:
  service.enabled:
    - name: salt-minion
