output "cf_cert_arn" {

    value       = aws_acm_certificate.prod_cf.arn
    description = "CloudFront Certificate ARN"

}