# M8 — cPouta infrastructure for the template app: keypair, security
# group (SSH + app port), a network port, a floating IP, and the VM that
# cloud-init turns into a running app. This recreates M7 (the manual
# cPouta setup) as code.

# SSH keypair imported from your local public key so `terraform apply`
# never generates or stores a private key.
resource "openstack_compute_keypair_v2" "this" {
  name       = "${var.instance_name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# Security group scoped to exactly what the app needs: SSH in for
# debugging, and the app port cloud-init publishes (see
# ../cloud-init/user-data.yaml.tpl). Everything else stays closed;
# OpenStack's own default rules already allow all egress. The group is
# applied to the VM's network port below, not to the instance.
resource "openstack_networking_secgroup_v2" "this" {
  name        = "${var.instance_name}-sg"
  description = "template-app: SSH + app port (M8, cPouta)"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.this.id
}

resource "openstack_networking_secgroup_rule_v2" "app" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = var.app_port
  port_range_max    = var.app_port
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.this.id
}

# The project's internal network, looked up by name so the port below can
# reference it by id (`openstack network list` shows the name to put in
# terraform.tfvars).
data "openstack_networking_network_v2" "this" {
  name = var.network_name
}

# The VM's network interface, created explicitly instead of letting Nova
# create one implicitly from `network { name = … }` on the instance. Two
# reasons, and the first one is not optional:
#   1. Only a pre-created port has an id Terraform can hand to the
#      floating-ip association below. With an implicit port, the
#      instance's `network[0].port` attribute stays an empty string, and
#      associating a floating IP with port_id = "" means "disassociate" —
#      apply goes green while the address stays unmapped.
#   2. The port outlives the VM (Nova detaches a pre-created port on
#      delete, it never deletes it), so the rebuild demo in README.md
#      keeps both the floating IP and the internal fixed IP.
# The security group therefore has to sit on the PORT: with an explicit
# port, the instance's own `security_groups` attribute no longer applies.
resource "openstack_networking_port_v2" "this" {
  name               = "${var.instance_name}-port"
  network_id         = data.openstack_networking_network_v2.this.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.this.id]
}

# Floating IP allocated as its OWN resource — not inline on the instance —
# so it has its own lifecycle in Terraform's state. `prevent_destroy`
# enforces AC#2 (destroy + re-apply must reuse the same address): Terraform
# will refuse to delete this resource, so the only way to tear down the VM
# is to leave the FIP alone. See README.md for the exact rebuild command
# and for how to release the IP for real at course end.
resource "openstack_networking_floatingip_v2" "this" {
  pool = var.external_network_name

  lifecycle {
    prevent_destroy = true
  }
}

# The VM itself. user_data is rendered from TASK-6's cloud-init template —
# it installs Docker and starts the app's docker-compose stack from GHCR
# on first boot, no SSH required.
resource "openstack_compute_instance_v2" "this" {
  name              = var.instance_name
  image_name        = var.image_name
  flavor_name       = var.flavor_name
  key_pair          = openstack_compute_keypair_v2.this.name
  availability_zone = var.availability_zone

  network {
    port = openstack_networking_port_v2.this.id
  }

  user_data = templatefile("${path.module}/../cloud-init/user-data.yaml.tpl", {
    ghcr_owner = var.ghcr_owner
  })
}

# Association kept as its own resource (instead of a `floating_ip` field on
# the instance) so the VM can be destroyed and recreated without touching
# the floating IP resource above — this is what makes the AC#2 rebuild
# demo work: destroy the instance, re-apply, same address comes back. The
# link is floating IP → PORT (that is how Neutron models it, and why the
# port above is created explicitly); the VM only borrows the port, so the
# association survives the rebuild untouched. See README.md section 4.
resource "openstack_networking_floatingip_associate_v2" "this" {
  floating_ip = openstack_networking_floatingip_v2.this.address
  port_id     = openstack_networking_port_v2.this.id
}
