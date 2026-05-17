#!/usr/bin/env bash
set -euo pipefail

rm -rf kubernetes/generated

python3 kubestack.py generate

kubectl apply --server-side -f kubernetes -R --force-conflicts