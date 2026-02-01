
output "cloudfront_key_pair_id" {
    value = aws_cloudfront_public_key.gallery_signer.id
  
}

output "cloudfront_admin_domain_name" {
    value = aws_cloudfront_distribution.admin.domain_name
  
}

output "cloudfront_web_domain_name" {
    value = aws_cloudfront_distribution.web.domain_name
  
}

output "cloudfront_gallery_domain_name" {
    value = aws_cloudfront_distribution.gallery.domain_name
  
}

output "cloudfront_admin_arn" {
    value = aws_cloudfront_distribution.admin.arn
  
}

output "cloudfront_web_arn" {
    value = aws_cloudfront_distribution.web.arn
  
}

output "cloudfront_gallery_arn" {
    value = aws_cloudfront_distribution.gallery.arn
  
}