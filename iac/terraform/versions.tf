# Terraform + provider version constraints (M8 — Infrastructure as Code).
#
# No backend block on purpose: this is a course exercise, so state lives
# locally (terraform.tfstate, gitignored) unless a group deliberately sets
# up a shared backend later. Auth to cPouta comes from clouds.yaml / the
# OS_CLOUD env var, never from hardcoded credentials — see README.md.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
  }
}

# Empty on purpose: the provider reads OS_CLOUD (and clouds.yaml) from the
# environment. That way nobody accidentally commits a cloud name or
# credentials into this file. See README.md "clouds.yaml".
provider "openstack" {}
