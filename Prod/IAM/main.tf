
############################################
# IAM User
############################################
resource "aws_iam_user" "this" {
  name = "galleryUser"
  tags = {
    ManagedBy = "terraform"
  }
}

############################################
# Policy: Full access ONLY to this bucket
############################################

data "aws_iam_policy_document" "cyberduck_user_policy" {

  #
  # Allow listing all buckets (Cyberduck needs this)
  #
  statement {
    sid    = "AllowListAllBuckets"
    effect = "Allow"

    actions = [
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation"
    ]

    resources = ["*"]
  }

  #
  # Full access to the single allowed bucket
  #
  statement {
    sid    = "AllowFullAccessToGalleryBucket"
    effect = "Allow"

    actions = ["s3:*"]

    resources = [
      "arn:aws:s3:::${var.gallery_bucket_name}",
      "arn:aws:s3:::${var.gallery_bucket_name}/*"
    ]
  }

  #
  # Explicitly deny access to ALL other buckets
  #
  statement {
    sid    = "DenyAccessToOtherBuckets"
    effect = "Deny"

    actions = ["s3:*"]

    not_resources = [
      "arn:aws:s3:::${var.gallery_bucket_name}",
      "arn:aws:s3:::${var.gallery_bucket_name}/*"
    ]
  }
}

resource "aws_iam_user_policy" "this" {
  name   = "${aws_iam_user.this.name}-s3-${var.gallery_bucket_name}-full"
  user   = aws_iam_user.this.name
  policy = data.aws_iam_policy_document.cyberduck_user_policy.json
}
