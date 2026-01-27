locals {

  lambda_dir   = "${path.module}/lambda"
  lambda_files = fileset(local.lambda_dir, "**/*")

  website_dir   = "${path.module}/website"
  website_files = fileset(local.website_dir, "**/*")
}


variable "gallery_retention_days" {
  description = "Number of days to retain gallery objects before deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.gallery_retention_days >= 1 && var.gallery_retention_days <= 3650
    error_message = "retention_days must be between 1 and 3650."
  }
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