output "floating_ip" {
  description = "Public (floating) IP address of the VM. Stays the same across the AC#2 rebuild demo (see README.md)."
  value       = openstack_networking_floatingip_v2.this.address
}

output "ssh_command" {
  description = "Ready-to-paste SSH command, in case you need to debug on the box."
  value       = "ssh ubuntu@${openstack_networking_floatingip_v2.this.address}"
}

output "app_url" {
  description = "Direct URL to the app once cloud-init has finished (may take a minute or two after apply)."
  value       = "http://${openstack_networking_floatingip_v2.this.address}:${var.app_port}"
}

output "app_url_nip_io" {
  description = "Same app, via a nip.io hostname instead of a bare IP (kursplan M7/M8: \"floating-IP/nip.io-URL\")."
  value       = "http://${replace(openstack_networking_floatingip_v2.this.address, ".", "-")}.nip.io:${var.app_port}"
}
