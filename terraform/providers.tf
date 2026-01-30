terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

############################
# AWS Provider
############################

provider "aws" {
  region = "us-east-2"
}

############################
# Cloudflare Provider
############################

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
