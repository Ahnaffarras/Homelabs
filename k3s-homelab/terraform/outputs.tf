output "master_ip" {
  description = "IP address node master k3s"
  value       = var.master_ip
}

output "worker_ips" {
  description = "Daftar IP address worker node k3s"
  value       = local.worker_ips
}

output "master_name" {
  description = "Nama domain libvirt node master"
  value       = local.master_name
}

output "worker_names" {
  description = "Daftar nama domain libvirt worker node"
  value       = local.worker_names
}

output "ssh_master" {
  description = "Perintah SSH cepat ke master"
  value       = "ssh ${var.vm_user}@${var.master_ip}"
}

output "ssh_workers" {
  description = "Perintah SSH cepat ke setiap worker"
  value       = [for ip in local.worker_ips : "ssh ${var.vm_user}@${ip}"]
}

output "ansible_inventory_hint" {
  description = "Ringkasan untuk dicocokkan dengan ansible/inventory/hosts.ini"
  value = {
    master  = var.master_ip
    workers = local.worker_ips
  }
}
