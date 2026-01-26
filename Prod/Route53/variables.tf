variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for example.com"
  type        = string
}

variable "root_domain" {
  description = "The root domain, e.g. example.com"
  type        = string
}

variable "web_sub_domain" {
  description = "Subdomain label for web (e.g. web)"
  type        = string
}

variable "gallery_sub_domain" {
  description = "Subdomain label for admin (e.g. admin)"
  type        = string
}

variable "admin_sub_domain" {
  description = "Subdomain label for gallery/photos (e.g. photos)"
  type        = string
}

# Your CloudFront distribution
variable "cloudfront_admin_domain_name" {
  description = "CloudFront distribution domain name, e.g. d123abcd.cloudfront.net"
  type        = string
}
# Your CloudFront distribution
variable "cloudfront_web_domain_name" {
  description = "CloudFront distribution domain name, e.g. d123abcd.cloudfront.net"
  type        = string
}
# Your CloudFront distribution
variable "cloudfront_gallery_domain_name" {
  description = "CloudFront distribution domain name, e.g. d123abcd.cloudfront.net"
  type        = string
}

variable "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID (always the same value, but pass it in explicitly)"
  type        = string
  default     = "Z2FDTNDATAQYW2"
}
