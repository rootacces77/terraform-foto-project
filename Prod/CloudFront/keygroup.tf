############################################################
# CloudFront Public Key
############################################################
data "aws_kms_public_key" "by_alias_arn" {
  key_id = var.cf_public_key_arn
}

resource "aws_cloudfront_public_key" "gallery_signer" {
  name        = "cf-key"
  comment     = "Public key used to validate signed cookies/URLs for gallery access."
  encoded_key = data.aws_kms_public_key.by_alias_arn.public_key
}

############################################################
# CloudFront Key Group (this is what you reference in trusted_key_groups)
############################################################
resource "aws_cloudfront_key_group" "gallery_signer" {
  name    = var.cf_key_group_name
  comment = "Key group used by CloudFront behaviors to trust signed cookies/URLs."
  items   = [aws_cloudfront_public_key.gallery_signer.id]
}