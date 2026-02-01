variable "acm_certificate_arn" {
    type = string
    description = "ACM Certificate ARN"
  
}

variable "website_bucket_regional_domain_name" {
    type = string
    description = "S3 Website Bucket Domain Name"

}

variable "gallery_bucket_regional_domain_name" {
    type = string
    description = "S3 Gallery Bucket Domain Name"

}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}


variable "folder_prefix" {
    type = string
    description = "Folder prefi where client folders are stored example /gallery/*"
    default = "gallery"
  
}


variable "cf_public_key_pem" {
    type = string
  
}
variable "cf_key_group_name" {
    type = string
    description = "cf_key_group_name"
    default = "cf-keygroup"
}


variable "api_open_origin_domain_name" {
  description = "Domain name for the /open endpoint origin Example: abc123.execute-api.eu-central-1.amazonaws.com"
  type        = string
}

variable "open_origin_path" {
  description = "Optional origin path if your API stage is in the path, e.g. /prod. Leave empty if not needed."
  type        = string
  default     = "/prod"
}

variable "admin_alias" {
    type = string
  
}

variable "gallery_alias" {
    type = string
  
}

variable "web_alias" {
    type = string 
  
}