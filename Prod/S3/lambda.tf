#############################
# Lambda S3 Bucket
#############################
module "lambda_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket        = "lambda-bucket-1231412456"
  force_destroy = true

  # Recommended when using CloudFront as the only public entry point
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Strong defaults
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  # Optional: serve index.html / error.html via CloudFront (recommended approach)
  # NOTE: This does NOT create a public "website endpoint"; CloudFront will request objects like /index.html
  tags = {
    Name        = "lambda-bucket"
    Environment = "PROD"
    Terraform   = "true"
  }
}

resource "aws_s3_object" "lambda" {
  for_each = {
    for f in local.lambda_files :
    f => f
    # Exclude "directories" if any tooling produces them (rare with fileset)
    if !endswith(f, "/")
  }

  bucket = module.lambda_bucket.s3_bucket_id

  # Keep directory structure in S3
  key    = each.value
  source = "${local.lambda_dir}/${each.value}"

  # Ensures changes trigger re-upload
  etag = filemd5("${local.lambda_dir}/${each.value}")

}
