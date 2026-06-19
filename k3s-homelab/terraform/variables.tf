variable "libvirt_uri" {
  description = "URI koneksi ke libvirt (QEMU/KVM)"
  type        = string
  default     = "qemu:///system"
}

variable "cluster_name" {
  description = "Prefix nama untuk semua resource cluster"
  type        = string
  default     = "k3s"
}

# ============================================================
# Storage Pool
# ============================================================
variable "pool_name" {
  description = "Nama libvirt storage pool"
  type        = string
  default     = "k3s-pool"
}

variable "pool_path" {
  description = "Path direktori untuk menyimpan disk VM"
  type        = string
  default     = "/var/lib/libvirt/images/k3s"
}

# ============================================================
# Image & User
# ============================================================
variable "ubuntu_image_path" {
  description = "Path ke file Ubuntu cloud image (.img/.qcow2) di host"
  type        = string
  # Contoh: /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img
}

variable "vm_user" {
  description = "Username default yang dibuat di VM"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key yang akan ditambahkan ke semua VM"
  type        = string
  # Dapatkan dengan: cat ~/.ssh/id_rsa.pub
}

# ============================================================
# Network
# ============================================================
variable "network_cidr" {
  description = "CIDR untuk jaringan internal k3s"
  type        = string
  default     = "192.168.100.0/24"
}

variable "network_prefix_length" {
  description = "Prefix length jaringan (misal: 24 untuk /24)"
  type        = number
  default     = 24
}

variable "network_gateway" {
  description = "IP gateway jaringan k3s"
  type        = string
  default     = "192.168.100.1"
}

variable "master_ip" {
  description = "IP statis untuk node master"
  type        = string
  default     = "192.168.100.10"
}

variable "network_interface_name" {
  description = "Nama interface jaringan di dalam VM (ens3 untuk KVM, enp1s0 bisa berbeda)"
  type        = string
  default     = "ens3"
}

variable "dns_servers" {
  description = "Daftar DNS server"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

# ============================================================
# Master Node
# ============================================================
variable "master_vcpu" {
  description = "Jumlah vCPU untuk node master"
  type        = number
  default     = 2
}

variable "master_memory" {
  description = "RAM (MB) untuk node master"
  type        = number
  default     = 2048
}

variable "master_disk_size" {
  description = "Ukuran disk (GB) untuk node master"
  type        = number
  default     = 20
}

# ============================================================
# Worker Nodes
# ============================================================
variable "worker_count" {
  description = "Jumlah worker node"
  type        = number
  default     = 2
}

variable "worker_vcpu" {
  description = "Jumlah vCPU untuk setiap worker node"
  type        = number
  default     = 1
}

variable "worker_memory" {
  description = "RAM (MB) untuk setiap worker node"
  type        = number
  default     = 1024
}

variable "worker_disk_size" {
  description = "Ukuran disk (GB) untuk setiap worker node"
  type        = number
  default     = 10
}

# ============================================================
# Cloud-init Packages
# ============================================================
variable "cloud_init_packages" {
  description = "Package yang diinstall via cloud-init saat VM pertama boot"
  type        = list(string)
  default = [
    "curl",
    "wget",
    "git",
    "vim",
    "net-tools",
    "htop",
    "qemu-guest-agent",
    "python3",
    "python3-pip"
  ]
}
