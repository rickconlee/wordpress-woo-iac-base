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
# Variables
############################

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "source_ami" {
  type    = string
  default = "ami-0a695f0d95cefc163" # Amazon Linux 2 (update if needed)
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

############################
# Source AMI
############################

source "amazon-ebs" "wordpress" {
  region        = var.region
  source_ami    = var.source_ami
  instance_type = var.instance_type
  ssh_username  = "ec2-user"

  ami_name      = "lolzify-wordpress-{{timestamp}}"

  subnet_filter {
    filters = {
      "tag:Name" = "*"
    }
    most_free = true
  }

  tags = {
    Name = "packer-lolzify-wordpress"
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
