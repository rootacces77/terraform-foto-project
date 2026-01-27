locals {
  fqdn_web    = "${var.web_sub_domain}"
  fqdn_admin  = "${var.gallery_sub_domain}"
  fqdn_gallery = "${var.admin_sub_domain}"
}

# -----------------------------
# web.<domain> -> CloudFront
# -----------------------------
resource "aws_route53_record" "web_a" {
  zone_id = var.hosted_zone_id
  name    = local.fqdn_web
  type    = "A"

  alias {
    name                   = var.cloudfront_web_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "web_aaaa" {
  zone_id = var.hosted_zone_id
  name    = local.fqdn_web
  type    = "AAAA"

  alias {
    name                   = var.cloudfront_web_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------
# admin.<domain> -> CloudFront
# -----------------------------
resource "aws_route53_record" "admin_a" {
  zone_id = var.hosted_zone_id
  name    = local.fqdn_admin
  type    = "A"

  alias {
    name                   = var.cloudfront_admin_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "admin_aaaa" {
  zone_id = var.hosted_zone_id
  name    = local.fqdn_admin
  type    = "AAAA"

  alias {
    name                   = var.cloudfront_admin_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# -----------------------------
# photos/gallery.<domain> -> CloudFront
# -----------------------------
resource "aws_route53_record" "gallery_a" {
  zone_id = var.hosted_zone_id
  name    = local.fqdn_gallery
  type    = "A"

  alias {
    name                   = var.cloudfront_gallery_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "gallery_aaaa" {
  zone_id = var.hosted_zone_id
  name    = local.fqdn_gallery
  type    = "AAAA"

  alias {
    name                   = var.cloudfront_gallery_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}