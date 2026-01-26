module "acm" {
    source = "./ACM"

    www_domain = local.www_domain
    apex_domain = local.apex_domain

    domain_zone_id = local.domain_zone_id

  
}
module "secretmanager" {
    source = "./SecretManager"

    lambda_role_arn = module.lambda.lambda_role_arn
  
}

module "kms" {
    source = "./KMS"

    secret_manager_pk_id = module.secretmanager.secret_manager_pk_id
  
}

module "iam" {
    source = "./IAM"

    identity_center_user_email = local.identity_center_user_email

    target_account_id = local.target_account_id
    signer_api_execute_arn = module.apigateway.signer_api_execute_arn
  
}

module "s3" {
    source = "./S3"
  
}

module "lambda" {
    source = "./Lambda"

    lambda_bucket_name = module.s3.lambda_bucket_name

    cloudfront_private_key_secret_arn = module.secretmanager.lambda_private_key_secret_arn
    cloudfront_key_pair_id = module.cloudfront.cloudfront_key_pair_id

    lambda_zip_path = local.lambda_zip_path

    cloudfront_domain = local.gallery_domain


  
}

module "apigateway" {
    source = "./APIGateway"

    lambda_cookie_generator_arn  = module.lambda.lambda_role_arn
    lambda_cookie_generator_name = module.lambda.lambda_cookie_generator_name
  
}

module "cloudfront" {
    source = "./CloudFront"

    acm_certificate_arn = module.acm.cf_cert_arn
    
    gallery_bucket_regional_domain_name = module.s3.gallery_bucket_regional_domain_name
    website_bucket_regional_domain_name = module.s3.website_bucket_regional_domain_name

    cf_public_key_arn = module.kms.cf_public_key_arn

}

module  "route53" {
    source = "./Route53"

    gallery_sub_domain = local.gallery_domain
    web_sub_domain     = local.www_domain
    root_domain = local.apex_domain
    admin_sub_domain = local.admin_domain

    hosted_zone_id = local.domain_zone_id
    
    cloudfront_admin_domain_name    = module.cloudfront.cloudfront_admin_domain_name
    cloudfront_web_domain_name      = module.cloudfront.cloudfront_web_domain_name
    cloudfront_gallery_domain_name  = module.cloudfront.cloudfront_gallery_domain_name



}

module "organization" {
    source = "./Organization"
  
}