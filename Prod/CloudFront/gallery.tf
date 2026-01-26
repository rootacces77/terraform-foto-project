############################################################
# 3) GALLERY Distribution (signed cookies required)
############################################################
resource "aws_cloudfront_distribution" "gallery" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = var.price_class

  #aliases = [var.gallery_alias]

  # Optional: if you have a landing page in the gallery bucket:
  # default_root_object = "${var.folder_prefix}/index.html"

  origin {
    origin_id                = "s3-gallery-origin"
    domain_name              = var.gallery_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-gallery-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # Enforce signed cookies/URLs via trusted key group
    trusted_key_groups = [aws_cloudfront_key_group.gallery_signer.id]

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = false
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}