output "group" {
  description = "Autoscaling group name"
  value       = var.group
}

output "install_path" {
  description = "Installation path for autoscaling tools"
  value       = var.install_path
}

output "config_file" {
  description = "Path to autoscaling configuration file"
  value       = "${var.install_path}/config/${var.group}.json"
}
