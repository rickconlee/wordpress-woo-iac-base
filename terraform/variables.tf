##########################
# Variables for AWS 
##########################




##########################
# Variables for cloudflare
##########################

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}