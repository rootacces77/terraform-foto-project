  ############################################
  # Gallery Bucket Policy
  ############################################

data "aws_iam_policy_document" "gallery_bucket_policy" {

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
    resources = ["${var.gallery_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [var.cloudfront_gallery_arn]
    }
  }
  ############################################
  # Deny delete on /site/* for one principal
  ############################################
  statement {
    sid    = "DenyDeleteSiteForSpecificPrincipal"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = [var.denied_site_delete_principal_arn]
    }

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion"
    ]

    resources = [
      "${var.gallery_bucket_arn}/site/*"
    ]
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
      var.gallery_bucket_arn,
      "${var.gallery_bucket_arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "gallery" {
  bucket = var.gallery_bucket_name
  policy = data.aws_iam_policy_document.gallery_bucket_policy.json
}