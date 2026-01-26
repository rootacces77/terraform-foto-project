#############################
# CloudFront Certificate 
#############################
#CREATE AND VALIDATE CERTIFICATE THAT WILL BE USED BY CF
resource "aws_acm_certificate" "prod_cf" {
  domain_name               =  var.apex_domain
  subject_alternative_names = [var.www_domain]


  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "PROD-CERT"
    Environment = "PROD"
  }
}



# CREATE DNS VALIDATION RECORD(S) IN MANAGEMENT USING ASSUMED ROLE
resource "aws_route53_record" "prod_cf_validation" {

  # Turn the set(domain_validation_options) into a map keyed by domain_name
  for_each = {
    for dvo in aws_acm_certificate.prod_cf.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.domain_zone_id

  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# VALIDATE CERT
resource "aws_acm_certificate_validation" "prod_cf" {
  certificate_arn = aws_acm_certificate.prod_cf.arn

  validation_record_fqdns = [
    for r in aws_route53_record.prod_cf_validation : r.fqdn
  ]
}
