#############################################
# Create Lambda-CloudFront Key Pair
############################################
resource "tls_private_key" "cf_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "cf_key" {
  key_name   = "cf-key"
  public_key = tls_private_key.cf_key.public_key_openssh
}

#Store private key in secret manager
resource "aws_secretsmanager_secret_version" "lambda_private_key_value" {
  secret_id     = var.secret_manager_pk_id
  secret_string = tls_private_key.cf_key.private_key_pem
}