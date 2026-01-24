resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac-s3-website-and-gallery"
  description                       = "OAC for website and gallery S3 origins"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = var.price_class

  # Serve website bucket /web/index.html by default
  default_root_object = "web/index.html"

  aliases = var.aliases

  # -----------------------
  # Origins
  # -----------------------
  origin {
    origin_id                = "s3-website-origin"
    domain_name              = var.website_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  origin {
    origin_id                = "s3-gallery-origin"
    domain_name              = var.gallery_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # -----------------------
  # Default behavior: Website
  # -----------------------
  default_cache_behavior {
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    compress = true
  }

  # -----------------------
  # /web/* -> Website origin
  # -----------------------
  ordered_cache_behavior {
    path_pattern           = "/web/*"
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    compress = true
  }

  # -----------------------
  # /admin/* -> Website origin
  # -----------------------
  ordered_cache_behavior {
    path_pattern           = "/admin/*"
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # Admin pages usually should not be cached aggressively (optional).
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    compress = true
  }

  # -----------------------
  # /clients/* -> Gallery origin, signed cookies required
  # -----------------------
  ordered_cache_behavior {
    path_pattern           = "/${var.folder_prefix}/*"
    target_origin_id       = "s3-gallery-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    # Signed cookies validation is enforced by trusting a key group
    trusted_key_groups = [var.trusted_key_group_id]

    # Gallery images can be cached (CloudFront still requires valid cookies to serve)
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    compress = true
  }

  # -----------------------
  # TLS / cert
  # -----------------------

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}