############################################
# IAM Role for Lambda COOKIE-GENERATOR
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


# SecretManager
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

# S3
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

# DynamoDB
data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    sid    = "AllowShareLinksTableReadWrite"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
      "dynamodb:Query"
    ]

    resources = [
      var.dynamodb_table_arn,
      "${var.dynamodb_table_arn}/index/*"
    ]
  }

}

resource "aws_iam_policy" "lambda_dynamodb" {
  name   = "lambda-dynamodb-share-links"
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

############################################
# IAM Role for Lambda THUMB-GENERATOR
############################################

resource "aws_iam_role" "lambda_thumb" {
  name               = "lambda-thumb-role-1234"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# CloudWatch Logs permissions
resource "aws_iam_role_policy_attachment" "lambda_basic_logs2" {
  role       = aws_iam_role.lambda_thumb.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3
resource "aws_iam_role_policy" "lambda_thumb_s3_inline" {
  name = "lambda-thumb-s3-inline"
  role = aws_iam_role.lambda_thumb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read originals (only gallery/)
      {
        Sid    = "ReadGallery"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::${var.gallery_bucket_name}/gallery/*"
        ]
      },

      # Write + Head thumbs (thumbs/)
      # This covers:
      # - thumbs/<album>/thumb-of-*.jpg
      # - thumbs/<album>/   (your folder marker object ending with '/')
      {
        Sid    = "WriteThumbs"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:HeadObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.gallery_bucket_name}/thumbs/*"
        ]
      },

      # Optional: ListBucket (only if you ever list; safe to keep)
      {
        Sid    = "ListBucketLimited"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.gallery_bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = ["gallery/*", "thumbs/*"]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_thumb_s3" {
  role       = aws_iam_role.lambda_thumb.name
  policy_arn = aws_iam_policy.lambda_list_bucket.arn
}