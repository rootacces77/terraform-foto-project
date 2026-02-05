module "tf_state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket = "tf-state-project-practice77-123"

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






resource "aws_dynamodb_table" "tf_lock" {
  name         = "tf-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute { 
              type = "S" 
              name = "LockID" 
            }
}