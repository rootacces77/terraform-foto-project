locals {
     apex_domain       = "project-practice.com"
     www_domain        = "www.${local.apex_domain}"
     gallery_domain    = "gallery.${local.apex_domain}"
     admin_domain      = "admin.${local.apex_domain}"
     admin_full_link   = "https://${local.admin_domain}/"

     domain_zone_id = data.aws_route53_zone.main.zone_id


     lambda_zip_path = "lambda.zip"

     gallery_retention_days = 30
}

data "aws_route53_zone" "main" {
  name         = local.apex_domain
  private_zone = false
}

data "aws_caller_identity" "current" {}