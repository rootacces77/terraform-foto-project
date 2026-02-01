
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
data "aws_iam_policy_document" "bucket_only_full_access" {
  statement {
    sid     = "BucketAndObjectsFullAccess"
    effect  = "Allow"
    actions = ["s3:*"]

    resources = [
      "arn:aws:s3:::${var.gallery_bucket_name}",
      "arn:aws:s3:::${var.gallery_bucket_name}/*",
    ]
  }
}

resource "aws_iam_user_policy" "this" {
  name   = "${aws_iam_user.this.name}-s3-${var.gallery_bucket_name}-full"
  user   = aws_iam_user.this.name
  policy = data.aws_iam_policy_document.bucket_only_full_access.json
}
