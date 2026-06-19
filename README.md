# K3s 3-Node Cluster di QEMU/KVM — Terraform + Ansible

Provisioning otomatis 3 VM (1 master + 2 worker) dan instalasi cluster [K3s](https://k3s.io) di atasnya, menggunakan **Terraform** (provider `dmacvicar/libvirt`) untuk membuat VM dan **Ansible** untuk konfigurasi OS + instalasi K3s.

Dibuat untuk dijalankan di mesin yang sudah punya **QEMU/KVM + virt-manager** terinstall (sesuai kondisi Anda saat ini).

---

## Daftar Isi

1. [Arsitektur](#arsitektur)
2. [Struktur Folder](#struktur-folder)
3. [Prasyarat](#prasyarat)
4. [Langkah 1 — Siapkan Ubuntu Cloud Image](#langkah-1--siapkan-ubuntu-cloud-image)
5. [Langkah 2 — Install Provider Terraform untuk Libvirt](#langkah-2--install-provider-terraform-untuk-libvirt)
6. [Langkah 3 — Siapkan SSH Key](#langkah-3--siapkan-ssh-key)
7. [Langkah 4 — Konfigurasi Terraform (`terraform.tfvars`)](#langkah-4--konfigurasi-terraform-terraformtfvars)
8. [Langkah 5 — Deploy Otomatis (cara cepat)](#langkah-5--deploy-otomatis-cara-cepat)
9. [Langkah 5 (Alternatif) — Deploy Manual Step-by-Step](#langkah-5-alternatif--deploy-manual-step-by-step)
10. [Verifikasi Cluster](#verifikasi-cluster)
11. [Troubleshooting](#troubleshooting)
12. [Cleanup / Destroy](#cleanup--destroy)
13. [Ide Pengembangan Lanjutan](#ide-pengembangan-lanjutan)

---

## Arsitektur

```
                    ┌─────────────────────────────────────┐
                    │     Host: QEMU/KVM (libvirt)         │
                    │                                       │
                    │   Network: k3s-net (NAT, /24)         │
                    │                                       │
                    │  ┌──────────────┐                     │
                    │  │ k3s-master   │  192.168.100.10      │
                    │  │ (server)     │  2 vCPU / 2GB / 20GB │
                    │  └──────┬───────┘                     │
                    │         │                              │
                    │  ┌──────┴───────┐  ┌────────────────┐ │
                    │  │ k3s-worker-1 │  │ k3s-worker-2    │ │
                    │  │ 192.168.100.11│  │ 192.168.100.12  │ │
                    │  └──────────────┘  └────────────────┘ │
                    └─────────────────────────────────────┘
```

- **Terraform** membuat 3 VM dari base image Ubuntu cloud (copy-on-write), lengkap dengan IP statis via cloud-init.
- **Ansible** masuk via SSH ke ketiga VM, menyiapkan OS (swap off, kernel module, sysctl), lalu install K3s server di master dan K3s agent di worker yang otomatis join ke master.
- Kubeconfig hasil cluster otomatis di-*fetch* ke laptop/mesin kontrol Anda, jadi `kubectl` bisa langsung dipakai dari luar VM.

---

## Struktur Folder

```
k3s-homelab/
├── README.md
├── .gitignore
├── terraform/
│   ├── provider.tf              # Provider libvirt
│   ├── variables.tf             # Semua variabel yang bisa dikustomisasi
│   ├── main.tf                  # Resource: pool, network, disk, VM
│   ├── outputs.tf                # Output IP master/worker
│   ├── terraform.tfvars.example  # Template config (copy -> terraform.tfvars)
│   └── cloud-init/
│       ├── user-data.yaml.tmpl       # Template cloud-init (user, SSH key, paket)
│       └── network-config.yaml.tmpl  # Template network statis tiap VM
├── ansible/
│   ├── ansible.cfg
│   ├── site.yml                  # Playbook utama
│   ├── group_vars/all.yml        # Variabel global (versi k3s, dll)
│   ├── inventory/
│   │   └── hosts.ini.example     # Contoh inventory (auto-generate oleh deploy.sh)
│   ├── kubeconfig/                # (auto-generate) hasil fetch kubeconfig
│   └── roles/
│       ├── common/tasks/main.yml      # Prep OS semua node
│       ├── k3s_master/tasks/main.yml  # Install K3s server
│       └── k3s_worker/tasks/main.yml  # Install K3s agent + join
└── scripts/
    ├── deploy.sh    # All-in-one: terraform apply + ansible-playbook
    ├── destroy.sh   # Hapus semua VM
    └── status.sh    # Cek cepat status cluster (kubectl get nodes)
```

---

## Prasyarat

Pastikan di mesin **host** (tempat QEMU/KVM jalan) sudah ada:

| Tool | Cek dengan | Install (Ubuntu/Debian) |
|---|---|---|
| QEMU/KVM + libvirt | `virsh list --all` | sudah ada sesuai cerita Anda |
| Terraform >= 1.3 | `terraform version` | lihat [terraform.io/downloads](https://developer.hashicorp.com/terraform/install) |
| Ansible-core >= 2.14 | `ansible --version` | `sudo apt install ansible` atau `pipx install ansible-core` |
| `jq` | `jq --version` | `sudo apt install jq` |
| `qemu-img` | `qemu-img --version` | biasanya sudah ada bareng QEMU |
| Build tools utk provider libvirt | - | `sudo apt install -y libvirt-dev gcc make` |
| `kubectl` (di laptop, opsional) | `kubectl version --client` | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |

User Anda harus jadi anggota grup `libvirt` dan `kvm`:

```bash
sudo usermod -aG libvirt,kvm $USER
newgrp libvirt
```

> **Catatan provider Terraform libvirt**: provider `dmacvicar/libvirt` di-build dari source oleh Terraform saat `terraform init` (memerlukan koneksi internet ke registry.terraform.io & github.com) dan membutuhkan `libvirt-dev` headers terpasang di host untuk proses build/link cgo. Jika host Anda offline, lihat opsi *vendor binary* di [repo provider ini](https://github.com/dmacvicar/terraform-provider-libvirt/releases).

---

## Langkah 1 — Siapkan Ubuntu Cloud Image

Anda menyebutkan sudah punya "image Ubuntu Server" — penting untuk dibedakan:

- ❌ **Ubuntu Server ISO** (installer biasa yang dipakai manual install via virt-manager) — **tidak bisa** dipakai otomatisasi Terraform+cloud-init.
- ✅ **Ubuntu Cloud Image (`.img`/`.qcow2`)** — image khusus yang sudah punya `cloud-init` bawaan, dirancang untuk provisioning otomatis. **Ini yang kita butuhkan.**

Download cloud image resmi (contoh Ubuntu 22.04 LTS "Jammy"):

```bash
sudo mkdir -p /var/lib/libvirt/images
sudo wget -O /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

Untuk Ubuntu 24.04 LTS ("Noble"), ganti URL ke:
`https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`

Pastikan permission bisa dibaca oleh proses libvirt/qemu:

```bash
sudo chmod 644 /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img
```

Catat path lengkap file ini — akan dipakai di `ubuntu_image_path` pada Langkah 4.

---

## Langkah 2 — Install Provider Terraform untuk Libvirt

Provider tidak perlu diinstall manual — `terraform init` akan otomatis mengunduhnya berdasarkan `terraform/provider.tf`. Anda hanya perlu memastikan dependency build (`libvirt-dev`, `gcc`, `make`) sudah ada (lihat tabel Prasyarat).

```bash
cd terraform
terraform init
```

Jika sukses, akan muncul folder `.terraform/` dan file `.terraform.lock.hcl`.

---

## Langkah 3 — Siapkan SSH Key

Jika belum punya SSH keypair:

```bash
ssh-keygen -t ed25519 -C "k3s-homelab" -f ~/.ssh/id_rsa -N ""
```

Tampilkan public key-nya (akan dipakai di `terraform.tfvars`):

```bash
cat ~/.ssh/id_rsa.pub
```

---

## Langkah 4 — Konfigurasi Terraform (`terraform.tfvars`)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`, minimal isi 2 variabel wajib:

```hcl
ubuntu_image_path = "/var/lib/libvirt/images/jammy-server-cloudimg-amd64.img"
ssh_public_key     = "ssh-ed25519 AAAAC3Nza... k3s-homelab"
```

Variabel lain (jumlah worker, RAM, vCPU, range IP, dll) sudah punya default yang masuk akal untuk belajar — lihat komentar di dalam file untuk detail tiap variabel. Beberapa yang sering perlu disesuaikan:

```hcl
worker_count = 2          # ubah jika mau >2 worker
master_memory = 2048       # MB
worker_memory = 2048       # MB
network_interface_name = "ens3"  # cek di Langkah Troubleshooting jika network tidak naik
```

---

## Langkah 5 — Deploy Otomatis (cara cepat)

Setelah `terraform.tfvars` siap, jalankan satu perintah ini dari root folder project:

```bash
./scripts/deploy.sh
```

Script ini akan otomatis:
1. `terraform init` + `terraform apply` → membuat 3 VM
2. Generate `ansible/inventory/hosts.ini` dari output Terraform
3. Menunggu sampai ketiga VM bisa diakses via SSH (cloud-init selesai)
4. Menjalankan `ansible-playbook site.yml` → install & join K3s
5. Menampilkan ringkasan IP + cara akses kubeconfig

Total waktu biasanya 5–10 menit tergantung spek host.

Jika SSH key Anda bukan `~/.ssh/id_rsa` (misalnya `id_ed25519`), set environment variable sebelum menjalankan:

```bash
SSH_PRIVATE_KEY=~/.ssh/id_ed25519 ./scripts/deploy.sh
```

---

## Langkah 5 (Alternatif) — Deploy Manual Step-by-Step

Kalau ingin paham/kontrol tiap tahap (atau `deploy.sh` gagal di tengah jalan), berikut versi manualnya:

### 5a. Provision VM dengan Terraform

```bash
cd terraform
terraform init
terraform plan      # review dulu apa yang akan dibuat
terraform apply
```

Lihat IP yang dihasilkan:

```bash
terraform output
```

Cek VM sudah muncul di virt-manager / virsh:

```bash
virsh list --all
```

### 5b. Generate Inventory Ansible

Salin contoh inventory lalu sesuaikan IP-nya dengan output Terraform di atas:

```bash
cd ../ansible
cp inventory/hosts.ini.example inventory/hosts.ini
nano inventory/hosts.ini   # sesuaikan ansible_host dan ansible_user
```

### 5c. Tunggu VM Siap

Cloud-init butuh waktu beberapa puluh detik setelah boot pertama. Tes SSH manual dulu:

```bash
ssh ubuntu@192.168.100.10   # ganti sesuai master_ip Anda
```

Jika berhasil masuk tanpa password, lanjut ke langkah berikut.

### 5d. Jalankan Ansible Playbook

```bash
cd ansible
ansible-playbook site.yml
```

Playbook ini menjalankan 4 play berurutan:
1. `common` role di semua node (matikan swap, load kernel module, sysctl)
2. `k3s_master` role di node master (install K3s server, generate token, fetch kubeconfig)
3. `k3s_worker` role di semua worker (install K3s agent, join pakai token dari master)
4. Verifikasi akhir — `kubectl get nodes` dari master sampai semua `Ready`

---

## Verifikasi Cluster

Setelah deploy selesai (baik via `deploy.sh` maupun manual), kubeconfig sudah otomatis tersimpan di:

```
ansible/kubeconfig/k3s.yaml
```

Gunakan dari laptop/mesin kontrol Anda (butuh `kubectl` terinstall):

```bash
export KUBECONFIG=$(pwd)/ansible/kubeconfig/k3s.yaml
kubectl get nodes -o wide
```

Output yang diharapkan (3 node, semua `Ready`):

```
NAME            STATUS   ROLES                  AGE   VERSION
k3s-master      Ready    control-plane,master   3m    v1.30.x+k3s1
k3s-worker-1    Ready    <none>                 2m    v1.30.x+k3s1
k3s-worker-2    Ready    <none>                 2m    v1.30.x+k3s1
```

Atau pakai script bantuan:

```bash
./scripts/status.sh
```

Cek pod sistem K3s juga jalan normal (`coredns`, `traefik`, `local-path-provisioner`, `metrics-server`):

```bash
kubectl get pods -A
```

Test deploy aplikasi sederhana:

```bash
kubectl create deployment nginx-test --image=nginx
kubectl expose deployment nginx-test --port=80 --type=NodePort
kubectl get svc nginx-test
```

---

## Troubleshooting

**VM menyala tapi tidak dapat IP / SSH timeout**
Kemungkinan nama interface jaringan di dalam image berbeda dari default `ens3`. Cek dengan virt-manager (buka console VM) atau via `virsh console <nama-vm>`, lalu jalankan `ip a` di dalam VM. Jika nama interface-nya beda (misal `enp1s0`), ubah `network_interface_name` di `terraform.tfvars`, lalu:
```bash
cd terraform
terraform taint libvirt_cloudinit_disk.master_init
terraform apply
```

**`terraform init` gagal build provider libvirt**
Pastikan `libvirt-dev`, `gcc`, dan `make` sudah terinstall di host (`sudo apt install -y libvirt-dev gcc make pkg-config`), serta koneksi internet ke `registry.terraform.io` dan `github.com` tidak diblok firewall/proxy.

**Ansible gagal connect: `Permission denied (publickey)`**
- Pastikan `ssh_public_key` di `terraform.tfvars` adalah public key (`.pub`) yang **pasangan private key-nya** Anda pakai di `ansible_ssh_private_key_file` / `SSH_PRIVATE_KEY`.
- Cek manual: `ssh -i ~/.ssh/id_rsa ubuntu@<ip-vm>`.

**Worker gagal join: `node_token belum tersedia`**
Pastikan Anda menjalankan `site.yml` secara utuh (bukan hanya role worker terpisah) — token di-generate saat play `k3s_master` jalan dan disimpan sebagai Ansible fact untuk play berikutnya dalam **proses Ansible yang sama**. Jangan jalankan `ansible-playbook site.yml --limit workers` di run terpisah.

**Mau install ulang dari awal**
```bash
./scripts/destroy.sh
rm -f ansible/inventory/hosts.ini
rm -rf ansible/kubeconfig/*.yaml
./scripts/deploy.sh
```

**Cek log instalasi K3s langsung di VM**
```bash
ssh ubuntu@<ip-master>
sudo journalctl -u k3s -f        # di master
sudo journalctl -u k3s-agent -f  # di worker
```

---

## Cleanup / Destroy

Untuk menghapus semua VM, disk, dan network yang dibuat (tapi **tidak** menghapus kubeconfig lokal Anda):

```bash
./scripts/destroy.sh
```

Atau manual:

```bash
cd terraform
terraform destroy
```

---

## Ide Pengembangan Lanjutan

Setelah cluster dasar jalan, beberapa hal yang bisa dieksplorasi untuk belajar lebih dalam:

- **HA control-plane**: tambah 2 master lagi + embedded etcd (`--cluster-init`) supaya tidak single point of failure.
- **Persistent storage**: ganti `local-path-provisioner` bawaan dengan Longhorn atau NFS provisioner.
- **Ingress kustom**: disable Traefik bawaan (`k3s_disable_components: ["traefik"]` di `group_vars/all.yml`) dan pasang NGINX Ingress / Cilium sendiri lewat Helm.
- **GitOps**: install ArgoCD atau Flux di atas cluster ini untuk belajar continuous deployment.
- **Monitoring**: pasang kube-prometheus-stack via Helm untuk belajar observability.
- **Scaling worker**: ubah `worker_count` di `terraform.tfvars` lalu `terraform apply` — VM baru otomatis ke-provision, tinggal jalankan ulang `ansible-playbook site.yml` untuk join-kan ke cluster.

---

## Lisensi

MIT — bebas dipakai, dimodifikasi, dan dibagikan untuk belajar.
