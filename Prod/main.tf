module "acm" {
    source = "./ACM"
    providers = {
      aws = aws.us-east-1
    }

    www_domain = local.www_domain
    apex_domain = local.apex_domain
    gallery_domain = local.gallery_domain
    admin_domain = local.admin_domain

    domain_zone_id = local.domain_zone_id

  
}

module "secretmanager" {
    source = "./SecretManager"
    providers = {
      aws = aws.eu-south-1
    }

    lambda_role_arn = module.lambda.lambda_role_arn
  
}

module "kms" {
    source = "./KMS"
    providers = {
      aws = aws.eu-south-1
    }

    secret_manager_pk_id = module.secretmanager.secret_manager_pk_id
  
}

/*
module "iam" {
    source = "./IAM"
    providers = {
      aws = aws.us-east-1
    }

    identity_center_user_email = local.identity_center_user_email

    target_account_id = local.target_account_id
    signer_api_execute_arn = module.apigateway.signer_api_execute_arn
  
}
*/

module "s3" {
    source = "./S3"
    providers = {
      aws = aws.eu-south-1
    }


}

module "lambda" {
    source = "./Lambda"
    providers = {
      aws = aws.eu-south-1
    }

    lambda_bucket_name = module.s3.lambda_bucket_name

    cloudfront_private_key_secret_arn = module.secretmanager.lambda_private_key_secret_arn
    cloudfront_key_pair_id = module.cloudfront.cloudfront_key_pair_id

    lambda_zip_path = local.lambda_zip_path

    cloudfront_domain = local.gallery_domain


  
}

module "cognito" {
    source = "./Cognito"
    providers = {
      aws = aws.eu-south-1
    }

    cognito_callback_urls = local.admin_domain
    cognito_logout_urls   = local.admin_domain


  
}

module "apigateway" {
    source = "./APIGateway"
    providers = {
      aws = aws.eu-south-1
    }

    lambda_cookie_generator_arn  = module.lambda.lambda_role_arn
    lambda_cookie_generator_name = module.lambda.lambda_cookie_generator_name

    cognito_issuer =  module.cognito.cognito_issuer
    cognito_user_pool_client_id = module.cognito.cognito_user_pool_client_id
  
}

module "cloudfront" {
    source = "./CloudFront"
    providers = {
      aws = aws.us-east-1
    }

    acm_certificate_arn = module.acm.cf_cert_arn
    
    gallery_bucket_regional_domain_name = module.s3.gallery_bucket_regional_domain_name
    website_bucket_regional_domain_name = module.s3.website_bucket_regional_domain_name


    api_open_origin_domain_name = module.apigateway.api_open_origin_domain_name

  #  cf_public_key_arn = module.kms.cf_public_key_arn
    cf_public_key_pem = module.kms.cf_public_key_pem

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
    providers = {
      aws = aws.us-east-1
    }
    source = "./Organization"
  
}

module "s3_policies" {
  source = "./S3-Policies"
    providers = {
      aws = aws.eu-south-1
    }

  website_bucket_arn = module.s3.website_bucket_arn
  website_bucket_name = module.s3.website_bucket_name
  cloudfront_admin_arn = module.cloudfront.cloudfront_admin_arn
  
}