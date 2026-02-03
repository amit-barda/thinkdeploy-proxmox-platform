terraform {
  required_version = ">= 1.6"
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "~> 2.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.pm_api_url
  pm_user         = var.pm_user
  pm_password     = var.pm_password
  pm_tls_insecure = var.pm_tls_insecure
}
