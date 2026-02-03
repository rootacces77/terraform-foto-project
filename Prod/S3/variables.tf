locals {

  lambda_dir   = "${path.module}/lambda"
  lambda_files = fileset(local.lambda_dir, "**/*")

  website_dir   = "${path.module}/website"
  website_files = fileset(local.website_dir, "**/*")

  gallery_dir   = "${path.module}/gallery"
  gallery_files = fileset(local.gallery_dir, "**/*")
}

locals {
  mime_types = {
    html = "text/html; charset=utf-8"
    css  = "text/css; charset=utf-8"
    js   = "application/javascript; charset=utf-8"
    json = "application/json; charset=utf-8"
    png  = "image/png"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
    svg  = "image/svg+xml"
    ico  = "image/x-icon"
    txt  = "text/plain; charset=utf-8"
    map  = "application/json; charset=utf-8"
    woff = "font/woff"
    woff2 = "font/woff2"
  }
}


variable "gallery_retention_days" {
  description = "Number of days to retain gallery objects before deletion."
  type        = number

  validation {
    condition     = var.gallery_retention_days >= 1 && var.gallery_retention_days <= 3650
    error_message = "retention_days must be between 1 and 3650."
  }
}

variable "gallery_policy_prefix" {
    type  = string
    default = "gallery/"
  
}
