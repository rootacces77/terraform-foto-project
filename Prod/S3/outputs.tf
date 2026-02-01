output "lambda_bucket_name" {
    value = module.lambda_bucket.s3_bucket_id

}

output "gallery_bucket_regional_domain_name" {
    value = module.gallery-bucket.s3_bucket_bucket_regional_domain_name
  
}

output "website_bucket_regional_domain_name" {
    value = module.static_site_bucket.s3_bucket_bucket_regional_domain_name
  
}

output "website_bucket_name" {
    value = module.static_site_bucket.s3_bucket_id
  
}

output "website_bucket_arn" {
    value = module.static_site_bucket.s3_bucket_arn
  
}

output "gallery_bucket_name" {
    value = module.gallery-bucket.s3_bucket_id
  
}

output "gallery_bucket_arn" {
    value = module.gallery-bucket.s3_bucket_arn
  
}