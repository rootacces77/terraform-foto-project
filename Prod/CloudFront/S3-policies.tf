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
    resources = ["${var.website_bucket_arn}/*"]

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
      var.website_bucket_arn,
      "${var.website_bucket_arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = var.website_bucket_name
  policy = data.aws_iam_policy_document.s3_bucket_policy_cloudfront_oac.json
}