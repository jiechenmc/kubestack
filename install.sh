#!/usr/bin/env bash
set -euo pipefail

INVENTORY="ansible/inventory.yaml"
PLAYBOOK="ansible/site.yaml"
TLS_CERT="./tls.crt"
TLS_KEY="./tls.key"
TLS_SECRET="local-selfsigned-tls"
TLS_NS="kube-system"
CHARTS_DIR="charts"
MANIFESTS="kubernetes/generated"

# ── Activate ansible venv ───────────────────────────────────────
. ~/.ansible/bin/activate

# ── Run Ansible playbook ────────────────────────────────────────
echo "── Running Ansible playbook ───────────────────────────────"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK"

python3 kubestack.py generate
kubectl wait --for=condition=established --timeout=120s crd --all
k apply --server-side -f kubernetes -R --force-conflicts