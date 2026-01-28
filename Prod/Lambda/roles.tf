############################################
# IAM Role for Lambda
############################################
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "lambda-role-1234"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# CloudWatch Logs permissions
resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


# Read Secrets
resource "aws_iam_role_policy" "lambda_read_cf_private_key_secret" {
  name = "lambda-read-cf-private-key-secret"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowReadPrivateKeySecret"
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.cloudfront_private_key_secret_arn
      }
    ]
  })
}

#List buckets
data "aws_iam_policy_document" "lambda_list_bucket" {
  statement {
    sid     = "AllowListGalleryBucket"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.gallery_bucket_name}"]
  }
}

resource "aws_iam_policy" "lambda_list_bucket" {
  name   = "lambda-list-gallery-bucket"
  policy = data.aws_iam_policy_document.lambda_list_bucket.json
}

resource "aws_iam_role_policy_attachment" "lambda_list_bucket" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_list_bucket.arn
}