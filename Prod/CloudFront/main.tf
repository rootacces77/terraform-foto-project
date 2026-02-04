resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "oac-s3-website-and-gallery"
  description                       = "OAC for website and gallery S3 origins"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}



data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_origin_request_policy" "cors_s3_origin" {
  name = "Managed-CORS-S3Origin"
}


# 30 days = 30 * 24 * 60 * 60 = 2,592,000 seconds
resource "aws_cloudfront_cache_policy" "ttl_30_days" {
  name        = "ttl-30-days"
  comment     = "Cache for 30 days. Good for immutable images/objects."
  default_ttl = 2592000
  max_ttl     = 2592000
  min_ttl     = 2592000

  parameters_in_cache_key_and_forwarded_to_origin {
    # Do NOT vary cache by headers/cookies unless you explicitly need it.
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    # If your image URLs never use query strings, keep this NONE.
    # If you use query strings for versioning (e.g. ?v=123), you may want:
    # query_string_behavior = "all" or "whitelist"
    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# 5 minutes = 300 seconds
resource "aws_cloudfront_cache_policy" "ttl_5_minutes" {
  name        = "ttl-5-minutes"
  comment     = "Cache for 5 minutes. Good for /list or small JSON manifests."
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    # If your /list endpoint uses query strings (e.g. /list?folder=test2/),
    # you MUST include that in the cache key, otherwise all folders share one cache.
    #
    # Recommended: whitelist only "folder"
    query_strings_config {
      query_string_behavior = "whitelist"
      query_strings {
        items = ["folder"]
      }
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}


# 1 year (365 days) = 365 * 24 * 60 * 60 = 31,536,000 seconds
resource "aws_cloudfront_cache_policy" "ttl_1_year" {
  name        = "ttl-1-year"
  comment     = "Cache for 1 year. Use only for immutable versioned objects."
  default_ttl = 31536000
  max_ttl     = 31536000
  min_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    # Keep none if your URLs don't use query strings.
    # If you use query strings for versioning, consider "all" or "whitelist".
    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

