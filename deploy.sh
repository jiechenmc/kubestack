source ~/.ansible/bin/activate
ansible-playbook -i ansible/inventory.yaml ansible/site.yaml
kubectl create secret tls local-selfsigned-tls \
  --cert=./tls.crt \
  --key=./tls.key \
  -n traefik

sudo firewall-cmd --permanent --zone=trusted --add-interface=cni0
sudo firewall-cmd --permanent --zone=trusted --add-interface=flannel.1
sudo firewall-cmd --reload