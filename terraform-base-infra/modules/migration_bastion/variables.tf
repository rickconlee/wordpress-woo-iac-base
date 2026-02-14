variable "name" {
  type        = string
  description = "Name prefix for bastion resources."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID."
}

variable "subnet_id" {
  type        = string
  description = "Public subnet ID for the bastion."
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use (must be your pre-baked AMI)."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type for the bastion."
  default     = "t3.micro"
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name for SSH."
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP in CIDR form, e.g. 203.0.113.10/32."
}

variable "db_security_group_id" {
  type        = string
  description = "Security group ID attached to RDS (aws_security_group.db.id)."
}

variable "efs_security_group_id" {
  type        = string
  description = "Security group ID attached to EFS mount targets (aws_security_group.efs.id)."
}

variable "vpc_cidr_block" {
  type        = string
  description = "VPC CIDR block (used to allow DNS to the VPC resolver)."
}

variable "tags" {
  type        = map(string)
  description = "Extra tags to apply."
  default     = {}
}

variable "enable" {
  type        = bool
  description = "Whether to create migration bastion resources."
  default     = true
}

variable "efs_file_system_id" {
  type        = string
  description = "EFS file system ID to mount, e.g. fs-abc123."
}

variable "efs_mount_point" {
  type        = string
  description = "Mount point on the bastion, e.g. /mnt/efs."
  default     = "/mnt/efs"
}

variable "efs_fstab_options" {
  type        = string
  description = "fstab options for EFS mount helper."
  default     = "tls,_netdev"
}

