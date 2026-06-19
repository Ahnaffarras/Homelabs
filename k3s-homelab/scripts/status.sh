#!/usr/bin/env bash
# ============================================================
# status.sh
# Cek cepat status cluster k3s menggunakan kubeconfig yang
# sudah di-fetch oleh Ansible.
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_FILE="$ROOT_DIR/ansible/kubeconfig/k3s.yaml"

if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "Kubeconfig tidak ditemukan di $KUBECONFIG_FILE"
  echo "Pastikan scripts/deploy.sh sudah selesai dijalankan."
  exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl belum terinstall di mesin lokal Anda."
  echo "Install dulu: https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi

echo "== Nodes =="
kubectl get nodes -o wide

echo ""
echo "== System Pods =="
kubectl get pods -A
