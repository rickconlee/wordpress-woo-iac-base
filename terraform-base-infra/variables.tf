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

variable "ami_image_id" {
  type = string  
}

variable "admin_ip" {
  type = string
}

variable "ssh_key_name" {
  type = string  
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

#############################
# Variables for Wordpress
#############################

# Database 

variable "mysql_user_name" {
  type = string
}

variable "mysql_user_password" {
  type      = string
  sensitive = true
}

variable "mysql_database_name" {
  type = string  
}