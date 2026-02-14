output "instance_id" {
  value       = var.enable ? aws_instance.bastion[0].id : null
  description = "Migration bastion instance ID."
}

output "public_ip" {
  value       = var.enable ? aws_instance.bastion[0].public_ip : null
  description = "Public IP for SSH."
}

output "security_group_id" {
  value       = var.enable ? aws_security_group.bastion[0].id : null
  description = "Security group ID attached to the bastion."
}
