############################################################
# 3) GALLERY Distribution (signed cookies required)
############################################################
resource "aws_cloudfront_distribution" "gallery" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = var.price_class

  aliases = [var.gallery_alias]

  # Optional: if you have a landing page in the gallery bucket:
  # default_root_object = "${var.folder_prefix}/index.html"

  origin {
    origin_id                = "s3-gallery-origin"
    domain_name              = var.gallery_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # origin for gallery ( S3 )
  default_cache_behavior {
    target_origin_id       = "s3-gallery-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # Enforce signed cookies/URLs via trusted key group
    trusted_key_groups = [aws_cloudfront_key_group.gallery_signer.id]

    cache_policy_id            = aws_cloudfront_cache_policy.ttl_30_days.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }


  # origin for /open /list endpoint (API Gateway/Lambda URL/ALB)
  origin {
    origin_id   = "api-origin"
    domain_name = var.api_open_origin_domain_name
    origin_path = var.open_origin_path

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # NEW: /open path must NOT require signed cookies
  ordered_cache_behavior {
    path_pattern           = "/open*"
    target_origin_id       = "api-origin"
    viewer_protocol_policy = "redirect-to-https"
 

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]


    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
   
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }

  # List
  ordered_cache_behavior {
    path_pattern           = "/list*"
    target_origin_id       = "api-origin"
    viewer_protocol_policy = "redirect-to-https"
 

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]


    cache_policy_id            = aws_cloudfront_cache_policy.ttl_5_minutes.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
   
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }


  # PUBLIC: site assets (no signed cookies required)
  ordered_cache_behavior {
    path_pattern           = "/site/*"
    target_origin_id       = "s3-gallery-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # IMPORTANT: no trusted_key_groups here, so it is public
    cache_policy_id            = aws_cloudfront_cache_policy.ttl_1_year.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
    compress                   = true
  }

    # PRIVATE: gallery images (signed cookies required)
  ordered_cache_behavior {
    path_pattern           = "/gallery/*"
    target_origin_id       = "s3-gallery-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    trusted_key_groups = [aws_cloudfront_key_group.gallery_signer.id]

    cache_policy_id            = aws_cloudfront_cache_policy.ttl_30_days.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
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