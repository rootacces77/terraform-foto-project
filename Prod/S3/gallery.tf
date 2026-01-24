#############################
# Gallery S3 Bucket
#############################
module "gallery-bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.0"

  bucket = "gallery-bucket-21365432"

  # Encryption
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning = {
    enabled = true
  }

  # Lifecycle: keep objects in STANDARD (no transitions) and delete after retention_days
  lifecycle_rule = [
    {
      id      = "expire-gallery-objects"
      enabled = true

      # Apply to all objects (recommended if the bucket is dedicated to galleries)
      filter = {
        prefix = ""
      }

      expiration = {
        days = var.gallery_retention_days
      }


      noncurrent_version_expiration = { days = var.gallery_retention_days }
      abort_incomplete_multipart_upload_days = 7

    }
  ]


  force_destroy = false
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  # Block public access
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true


  tags = {
    Name        = "gallery-bucket"
    Environment = "PROD"
    Terraform   = "true"
  }
}