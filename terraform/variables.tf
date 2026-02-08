##########################
# Variables for AWS 
##########################

variable "aws_access_key_id"{
  type = string
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}


#############################
# Variables for cloudflare
#############################

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}