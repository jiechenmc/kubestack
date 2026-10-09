#!/usr/bin/env bash
set -euo pipefail

rm -rf kubernetes/generated

python3 kubestack.py generate

# apply everything under kubernetes/ except the raw helm charts (rendered into kubernetes/generated)
args=()
for entry in kubernetes/*; do
  [[ "$entry" == kubernetes/helm ]] && continue
  args+=(-f "$entry")
done

kubectl apply --server-side -R --force-conflicts "${args[@]}"