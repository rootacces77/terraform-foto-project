############################################################
# 1) WEB Distribution
############################################################
resource "aws_cloudfront_distribution" "web" {
  enabled         = true
  is_ipv6_enabled = true
  price_class     = var.price_class

  aliases = [var.web_alias]

  # / -> /web/index.html
  default_root_object = "index.html"

  origin {
    origin_id                = "s3-website-origin"
    domain_name              = var.website_bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_path = "/website"
  }

  default_cache_behavior {
    target_origin_id       = "s3-website-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    cache_policy_id            = aws_cloudfront_cache_policy.ttl_1_year.id
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