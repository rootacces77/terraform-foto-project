
variable "lambda_bucket_name" {
    type = string
    description = "Lambda bucket name"
  
}

variable "lambda_cookie_zip_path" {
    type = string
    description = "Lambda cookie-generator path to zip file"
  
}
variable "lambda_thumb_zip_path" {
    type = string
    description = "Lambda thumb generator path to zip file"
  
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
    default = 43200
}  # 7 days
variable "max_ttl_seconds" {
     type = number
     default = 43200 
}     # 30 days

variable "default_link_ttl_seconds" {
    type = number
    default = 86400
  
}
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

variable "gallery_bucket_arn" {
    type = string
    description = "Gallery Bucket ARN"
  
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

variable "list_cache_ttl_seconds" {
    type = number
    description = "Number in seconds that /list will cache in lambda "
    default = 300
  
}

variable "include_token_in_redirect" {
    type = string
    description = "Can gallery page call /list with token"
    default = "true"
  
}

variable "token_ttl_buffer_seconds" {
    type = number
    description = "After link expires how long to keep insert in DynamoDB in seconds"
    default = 3600
  
}


variable "dynamodb_table_arn" {
  type = string
}

variable "dynamodb_table_name" {
    type = string
  
}

variable "thumbs_prefix" {
    type = string
    default = "thumbs/"
  
}