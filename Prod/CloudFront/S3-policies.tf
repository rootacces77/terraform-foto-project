data "aws_iam_policy_document" "s3_bucket_policy_cloudfront_oac" {

  ############################################
  # CloudFront OAC -> S3 GetObject only
  ############################################
  statement {
    sid    = "AllowCloudFrontReadViaOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${module.static_site_bucket.s3_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.admin.arn]
    }
  }


  ############################################
  # Deny non-TLS for everyone
  ############################################
  statement {
    sid    = "DenyInsecureTransportForAll"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      module.static_site_bucket.s3_bucket_arn,
      "${module.static_site_bucket.s3_bucket_arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = module.static_site_bucket.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_bucket_policy_cloudfront_oac.json
}