locals {

  lambda_dir   = "${path.module}/lambda"
  lambda_files = fileset(local.lambda_dir, "**/*")

  website_dir   = "${path.module}/website"
  website_files = fileset(local.website_dir, "**/*")
}


variable "gallery_retention_days" {
  description = "Number of days to retain gallery objects before deletion."
  type        = number

  validation {
    condition     = var.gallery_retention_days >= 1 && var.gallery_retention_days <= 3650
    error_message = "retention_days must be between 1 and 3650."
  }
}
