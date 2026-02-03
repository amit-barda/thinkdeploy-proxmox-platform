output "api_tokens" {
  description = "API token IDs"
  value       = keys(var.api_tokens)
}
