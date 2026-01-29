terraform {
  required_version = ">= 1.6.0"

# Included providers

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

# Provider specific configuration items

provider "aws" {
  region = "us-east-2"
}