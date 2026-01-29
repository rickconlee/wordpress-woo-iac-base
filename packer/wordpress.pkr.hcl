packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.2.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

############################
# Variables (match terraform.tfvars)
############################

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "aws_region" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

############################
# Source AMI
############################

source "amazon-ebs" "wordpress" {
  region        = var.aws_region
  instance_type = "t2.micro"
  ssh_username  = "ec2-user"

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ami_name = "lolzify-${var.environment}-wordpress-{{timestamp}}"

  ############################
  # THIS IS THE CRITICAL PART
  # tfvars → env vars → AWS SDK
  ############################

  environment_vars = [
    "AWS_ACCESS_KEY_ID=${var.aws_access_key_id}",
    "AWS_SECRET_ACCESS_KEY=${var.aws_secret_access_key}",
    "AWS_DEFAULT_REGION=${var.aws_region}"
  ]

  tags = {
    Name        = "lolzify-wordpress"
    Environment = var.environment
    BuiltBy     = "packer"
  }
}

############################
# Build
############################

build {
  name    = "lolzify-wordpress-ami"
  sources = ["source.amazon-ebs.wordpress"]

  provisioner "ansible" {
    playbook_file = "../ansible/playbook.yml"
    user          = "ec2-user"

    extra_arguments = [
      "--extra-vars",
      "db_password=${var.db_password} environment=${var.environment}"
    ]
  }
}
