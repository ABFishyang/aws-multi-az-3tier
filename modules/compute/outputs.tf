output "instance_ids" {
  description = "Map of Web/App EC2 instance IDs (a, b)"
  value       = { for k, i in aws_instance.web : k => i.id }
}
