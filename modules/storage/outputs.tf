output "file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}
