# Variables for the M8 cPouta module. Defaults are chosen to work
# out-of-the-box on CSC's cPouta where a sensible cloud-wide default
# exists (flavor, image, floating-ip pool). Variables that are specific to
# YOUR project (network, GHCR owner) have no default — Terraform will
# refuse to apply until you set them, which is the point: copy
# terraform.tfvars.example to terraform.tfvars and fill them in.

variable "instance_name" {
  description = "Name of the VM instance (and prefix for the keypair/security group)."
  type        = string
  default     = "template-app"
}

variable "image_name" {
  description = "cPouta image to boot from. Check `openstack image list` for exact names available in your project."
  type        = string
  default     = "Ubuntu-24.04"
}

variable "flavor_name" {
  description = "cPouta flavor (size) for the VM. `standard.small` is enough for the two-container template app."
  type        = string
  default     = "standard.small"
}

variable "network_name" {
  description = "Name of the project's internal (tenant) network to attach the VM to. Project-specific — no default. Check `openstack network list`."
  type        = string
}

variable "external_network_name" {
  description = "Name of the external/floating-ip network pool. \"public\" is the standard pool name on cPouta."
  type        = string
  default     = "public"
}

variable "ssh_public_key_path" {
  description = "Path to your local SSH public key, imported into OpenStack as a keypair. Any key type/path works — override if yours lives elsewhere."
  type        = string
  default     = "~/.ssh/cpouta_ed25519.pub"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to reach SSH (port 22). Defaults to open for course convenience — narrow this to your own IP/subnet for anything beyond a throwaway lab VM."
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_port" {
  description = "Port the app (frontend/nginx) listens on and that the security group opens to the internet. Must match the port published in iac/cloud-init/user-data.yaml.tpl's docker-compose.yml."
  type        = number
  default     = 8080
}

variable "ghcr_owner" {
  description = "GHCR namespace (org/user) that publishes template-app-backend and template-app-frontend, e.g. your GitHub username. Same value used in .github/workflows/publish-images.yml. Passed into the cloud-init template via templatefile()."
  type        = string
}

variable "availability_zone" {
  description = "Optional cPouta availability zone. Leave null to let OpenStack pick the default."
  type        = string
  default     = null
}
