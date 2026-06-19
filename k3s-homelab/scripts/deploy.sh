#!/usr/bin/env bash
# ============================================================
# deploy.sh
# Otomatisasi penuh: Terraform apply -> generate inventory ->
# tunggu VM siap -> jalankan Ansible playbook k3s.
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.ini"

color() { printf "\033[1;36m%s\033[0m\n" "$1"; }
err()   { printf "\033[1;31m%s\033[0m\n" "$1" >&2; }

# ------------------------------------------------------------
# 0. Cek dependency
# ------------------------------------------------------------
for cmd in terraform ansible-playbook jq ssh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Error: '$cmd' tidak ditemukan. Install dulu sebelum lanjut."
    exit 1
  fi
done

if [ ! -f "$TF_DIR/terraform.tfvars" ]; then
  err "Error: $TF_DIR/terraform.tfvars belum ada."
  err "Jalankan: cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
  err "lalu edit nilainya (ubuntu_image_path, ssh_public_key, dll)."
  exit 1
fi

# ------------------------------------------------------------
# 1. Terraform: provision VM
# ------------------------------------------------------------
color "==> [1/4] Terraform init & apply"
cd "$TF_DIR"
terraform init -input=false
terraform apply -auto-approve

MASTER_IP=$(terraform output -raw master_ip)
WORKER_IPS_JSON=$(terraform output -json worker_ips)
mapfile -t WORKER_IPS < <(echo "$WORKER_IPS_JSON" | jq -r '.[]')
VM_USER=$(terraform output -raw ssh_master | sed -E 's/^ssh ([^@]+)@.*/\1/')

cd "$ROOT_DIR"

# ------------------------------------------------------------
# 2. Generate Ansible inventory dari output Terraform
# ------------------------------------------------------------
color "==> [2/4] Generate Ansible inventory"

{
  echo "[master]"
  echo "k3s-master ansible_host=${MASTER_IP}"
  echo ""
  echo "[workers]"
  i=1
  for ip in "${WORKER_IPS[@]}"; do
    echo "k3s-worker-${i} ansible_host=${ip}"
    i=$((i + 1))
  done
  echo ""
  echo "[k3s_cluster:children]"
  echo "master"
  echo "workers"
  echo ""
  echo "[k3s_cluster:vars]"
  echo "ansible_user=${VM_USER}"
  echo "ansible_ssh_private_key_file=${SSH_PRIVATE_KEY:-~/.ssh/id_rsa}"
  echo "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'"
  echo "ansible_python_interpreter=/usr/bin/python3"
} > "$INVENTORY_FILE"

color "Inventory tersimpan di: $INVENTORY_FILE"

# ------------------------------------------------------------
# 3. Tunggu semua VM bisa diakses via SSH
# ------------------------------------------------------------
color "==> [3/4] Menunggu semua VM siap menerima SSH (cloud-init)..."

ALL_IPS=("$MASTER_IP" "${WORKER_IPS[@]}")
for ip in "${ALL_IPS[@]}"; do
  printf "  Menunggu %s ... " "$ip"
  tries=0
  max_tries=60 # 60 x 5s = 5 menit
  until ssh -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            -i "${SSH_PRIVATE_KEY:-$HOME/.ssh/id_rsa}" \
            "${VM_USER}@${ip}" true 2>/dev/null; do
    tries=$((tries + 1))
    if [ "$tries" -ge "$max_tries" ]; then
      err "Timeout menunggu SSH di $ip"
      exit 1
    fi
    sleep 5
  done
  echo "siap"
done

# ------------------------------------------------------------
# 4. Jalankan Ansible playbook
# ------------------------------------------------------------
color "==> [4/4] Menjalankan Ansible playbook (install k3s)"
cd "$ANSIBLE_DIR"
ansible-playbook site.yml

color ""
color "============================================================"
color " Cluster k3s berhasil dibuat!"
color " Master : ${MASTER_IP}"
for ip in "${WORKER_IPS[@]}"; do
  color " Worker : ${ip}"
done
color ""
color " Untuk akses cluster dari laptop Anda:"
color "   export KUBECONFIG=${ANSIBLE_DIR}/kubeconfig/k3s.yaml"
color "   kubectl get nodes"
color "============================================================"
