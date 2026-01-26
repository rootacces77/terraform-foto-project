output "cf_public_key_arn" {
    value = aws_key_pair.cf_key.arn
  
}

output "cf_public_key_pem" {
    value = tls_private_key.cf_key.public_key_pem
  
}