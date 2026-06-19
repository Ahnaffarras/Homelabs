#!/usr/bin/env bash
# ============================================================
# destroy.sh
# Menghapus semua VM, network, dan storage pool yang dibuat
# Terraform. Kubeconfig lokal hasil fetch TIDAK otomatis dihapus.
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"

printf "\033[1;33mIni akan menghapus SEMUA VM k3s (master + worker) beserta disk-nya. Lanjut? [y/N] \033[0m"
read -r confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Dibatalkan."
  exit 0
fi

cd "$TF_DIR"
terraform destroy -auto-approve

echo "Selesai. Semua resource VM sudah dihapus."
echo "Catatan: ansible/inventory/hosts.ini dan ansible/kubeconfig/ tidak otomatis dihapus."
