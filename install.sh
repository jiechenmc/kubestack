#!/usr/bin/env bash
set -euo pipefail

python3 kubestack.py generate

sleep 5s

kubectl apply --server-side -f kubernetes -R --force-conflicts