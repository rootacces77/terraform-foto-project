locals {
     apex_domain = "project-practice.com"
     www_domain  = "www.${local.apex_domain}"
     gallery_domain = "gallery.${local.apex_domain}"
     admin_domain   = "admin.${local.apex_domain}"

     domain_zone_id = data.aws_route53_zone.main.zone_id

     identity_center_user_email = "project.practice77@gmail.com"
     target_account_id  =
     signer_api_execute_arn

     lambda_zip_path = "lambda.zip"
}

data "aws_route53_zone" "main" {
  name         = local.apex_domain
  private_zone = false
}
