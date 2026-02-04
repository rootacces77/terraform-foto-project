
variable "lambda_bucket_name" {
    type = string
    description = "Lambda bucket name"
  
}

variable "lambda_zip_path" {
    type = string
    description = "LambdaA path to zip file"
  
}


variable "cloudfront_domain" { 
    type = string
}
variable "cloudfront_key_pair_id" { 
    type = string 
}
variable "cloudfront_private_key_secret_arn" { 
    type = string 
}


variable "default_ttl_seconds" { 
    type = number 
    default = 604800
}  # 7 days
variable "max_ttl_seconds" {
     type = number
     default = 2592000 
}     # 14 days
variable "redirect_to_index" { 
    type = string
    default = "true" 
}

variable "cookie_secure" { 
    type = string
    default = "true"
 }
variable "cookie_httponly" { 
    type = string
    default = "true" 
}
variable "cookie_samesite" { 
    type = string
    default = "None" 
}
variable "cookie_set_max_age" { 
    type = string
    description = "Also set browser cookie policy"
    default = "true" 
}

variable "cookie_domain" { 
    type = string
    default = "" 
}  # set to "photos.example.com"

variable "cookie_path" { 
    type = string
    default = "/" 
}

variable "open_path" {
  description = "Path used in share_url returned by /sign (default /open)."
  type        = string
  default     = "/open"
}


variable "gallery_bucket_name" {
    type = string
    description = "Gallery Bucket Name"
  
}

variable "gallery_index_path" {
    type = string
    description = "Path to index.html"
    default = "/site/index.html"
  
}

variable "allowed_folder_prefix"{ 
    type = string 
    default = "gallery"
}