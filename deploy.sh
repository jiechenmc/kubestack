source ~/.ansible/bin/activate
ansible-playbook -i ansible/inventory.yaml ansible/site.yaml
kubectl create secret tls local-selfsigned-tls \
  --cert=./tls.crt \
  --key=./tls.key \
  -n kube-system

k apply -f kubernetes/ -R