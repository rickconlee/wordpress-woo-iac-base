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
# Variables (build metadata only)
############################

variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "environment" {
  type    = string
  default = "demo"
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
      name                = "al2023-ami-*-x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  ami_name = "lolzify-${var.environment}-wordpress-{{timestamp}}"

  tags = {
    Name        = "lolzify-wordpress"
    Environment = var.environment
    BuiltBy     = "packer"
    Purpose     = "wordpress-runtime"
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
  }
}
