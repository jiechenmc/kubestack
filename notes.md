### Cilium Behaviors

1. Picks the smallest MTU on host netdevs

- This picked 1280 from `tailscale0` (`enp4s0`/`wlp3s0` are 1500), so `cilium_host`/`cilium_vxlan` got 1280 and pods got a route MTU of 1230 after VXLAN overhead
- QUIC handshake packets are 1280 bytes with don't-fragment set, so they could never leave a pod: `cloudflared` failed with `failed to dial to edge with quic: timeout: handshake did not complete in time`
- TCP was unaffected because it negotiates its segment size to fit the MTU, which hid the problem (HTTP/2 tunnels worked)
- Fix: set the MTU explicitly with `--set MTU=1500` on the Cilium Helm install (`install_cilium` in `salt/state/kubernetes.sls`), giving pods 1450
- Check: `ip link show cilium_vxlan` on the host and `ip route` inside a pod (`default via ... mtu 1450`)
