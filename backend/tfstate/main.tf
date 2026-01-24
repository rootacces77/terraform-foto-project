module "tf_state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket = "tf-state-project-practice77"

  # Versioning
  versioning = {
    status = true
  }

  # Block public access
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Optional recommended extras
  #acl    = "private"
  force_destroy = true  # change to true if you want Terraform to delete non-empty buckets

  tags = {
    Name        = "tf-state-bucket"
    Environment = "practice"
    Terraform   = "true"
  }
}


resource "aws_s3_bucket_policy" "tf_state_org" {
  bucket = module.tf_state_bucket.s3_bucket_id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOrgUseBucketForTfState"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          module.tf_state_bucket.s3_bucket_arn,
          "${module.tf_state_bucket.s3_bucket_arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = local.org_id
          }
        }
      }
    ]
  })
}






resource "aws_dynamodb_table" "tf_lock" {
  name         = "tf-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute { 
              type = "S" 
              name = "LockID" 
            }
}