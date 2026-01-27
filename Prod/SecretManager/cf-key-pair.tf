############################################
# Lambda-CloudFront Private Key
############################################
resource "aws_secretsmanager_secret" "lambda_private_key" {
  name        = "lambda-cf-key"
  description = "Private key for Lambda-CF"

  tags = {
    Environment = "PROD"
  }
}


/*
resource "aws_secretsmanager_secret_policy" "deny_all_except_lambda" {
  secret_arn = aws_secretsmanager_secret.lambda_private_key.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Explicit deny for ANY principal who is NOT the Lambda role
      {
        Sid    = "DenyReadSecretUnlessLambdaRole",
        Effect = "Deny",
        Principal = "*",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = aws_secretsmanager_secret.lambda_private_key.arn,
        Condition = {
          StringNotEquals = {
            "aws:PrincipalArn" = var.lambda_role_arn
          }
        }
      }
    ]
  })
}
*/