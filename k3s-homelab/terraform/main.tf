locals {
  worker_ips = [for i in range(var.worker_count) : cidrhost(var.network_cidr, 11 + i)]

  master_name  = "${var.cluster_name}-master"
  worker_names = [for i in range(var.worker_count) : "${var.cluster_name}-worker-${i + 1}"]

  # Render cloud-init user-data (sama untuk semua node, beda hostname/ip)
  master_user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tmpl", {
    hostname = local.master_name
    vm_user  = var.vm_user
    ssh_key  = var.ssh_public_key
    packages = var.cloud_init_packages
  })

  master_network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tmpl", {
    ip_address  = var.master_ip
    prefix      = var.network_prefix_length
    gateway     = var.network_gateway
    dns_servers = var.dns_servers
    iface_name  = var.network_interface_name
  })

  worker_user_data = [
    for i in range(var.worker_count) : templatefile("${path.module}/cloud-init/user-data.yaml.tmpl", {
      hostname = local.worker_names[i]
      vm_user  = var.vm_user
      ssh_key  = var.ssh_public_key
      packages = var.cloud_init_packages
    })
  ]

  worker_network_config = [
    for i in range(var.worker_count) : templatefile("${path.module}/cloud-init/network-config.yaml.tmpl", {
      ip_address  = local.worker_ips[i]
      prefix      = var.network_prefix_length
      gateway     = var.network_gateway
      dns_servers = var.dns_servers
      iface_name  = var.network_interface_name
    })
  ]
}

# ============================================================
# Storage Pool — tempat menyimpan semua disk VM
# ============================================================
resource "libvirt_pool" "k3s_pool" {
  name = var.pool_name
  type = "dir"
  path = var.pool_path
}

# ============================================================
# Base Volume — image Ubuntu cloud yang sudah Anda download
# Semua VM akan "cloning" dari base image ini (copy-on-write)
# ============================================================
resource "libvirt_volume" "base_image" {
  name   = "${var.cluster_name}-base.qcow2"
  pool   = libvirt_pool.k3s_pool.name
  source = var.ubuntu_image_path
  format = "qcow2"
}

# ============================================================
# Network — jaringan privat NAT khusus untuk cluster k3s
# Semua VM mendapat IP statis agar mudah dikelola Ansible
# ============================================================
resource "libvirt_network" "k3s_net" {
  name      = "${var.cluster_name}-net"
  mode      = "nat"
  domain    = "${var.cluster_name}.local"
  addresses = [var.network_cidr]

  dns {
    enabled    = true
    local_only = false
  }

  dhcp {
    enabled = true
  }
}

# ============================================================
# Disk Volume per VM (master)
# ============================================================
resource "libvirt_volume" "master_disk" {
  name           = "${local.master_name}.qcow2"
  pool           = libvirt_pool.k3s_pool.name
  base_volume_id = libvirt_volume.base_image.id
  format         = "qcow2"
  size           = var.master_disk_size * 1024 * 1024 * 1024
}

# ============================================================
# Disk Volume per VM (worker)
# ============================================================
resource "libvirt_volume" "worker_disk" {
  count          = var.worker_count
  name           = "${local.worker_names[count.index]}.qcow2"
  pool           = libvirt_pool.k3s_pool.name
  base_volume_id = libvirt_volume.base_image.id
  format         = "qcow2"
  size           = var.worker_disk_size * 1024 * 1024 * 1024
}

# ============================================================
# Cloud-init: Master
# ============================================================
resource "libvirt_cloudinit_disk" "master_init" {
  name           = "${local.master_name}-cloudinit.iso"
  pool           = libvirt_pool.k3s_pool.name
  user_data      = local.master_user_data
  network_config = local.master_network_config
}

# ============================================================
# Cloud-init: Worker (per index)
# ============================================================
resource "libvirt_cloudinit_disk" "worker_init" {
  count          = var.worker_count
  name           = "${local.worker_names[count.index]}-cloudinit.iso"
  pool           = libvirt_pool.k3s_pool.name
  user_data      = local.worker_user_data[count.index]
  network_config = local.worker_network_config[count.index]
}

# ============================================================
# VM Domain: Master
# ============================================================
resource "libvirt_domain" "master" {
  name      = local.master_name
  memory    = var.master_memory
  vcpu      = var.master_vcpu
  cloudinit = libvirt_cloudinit_disk.master_init.id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.master_disk.id
  }

  network_interface {
    network_id     = libvirt_network.k3s_net.id
    addresses      = [var.master_ip]
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  qemu_agent = true
}

# ============================================================
# VM Domain: Worker
# ============================================================
resource "libvirt_domain" "worker" {
  count     = var.worker_count
  name      = local.worker_names[count.index]
  memory    = var.worker_memory
  vcpu      = var.worker_vcpu
  cloudinit = libvirt_cloudinit_disk.worker_init[count.index].id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.worker_disk[count.index].id
  }

  network_interface {
    network_id     = libvirt_network.k3s_net.id
    addresses      = [local.worker_ips[count.index]]
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  qemu_agent = true
}
