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

resource "aws_secretsmanager_secret_policy" "deny_all_except_lambda_and_oidc" {
  secret_arn = aws_secretsmanager_secret.lambda_private_key.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Deny everyone except the two roles
      {
        Sid       = "DenyUnlessLambdaOrOidc",
        Effect    = "Deny",
        Principal = "*",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",

          "secretsmanager:DeleteSecret",
          "secretsmanager:RestoreSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:RotateSecret",
          "secretsmanager:CancelRotateSecret",
          "secretsmanager:PutResourcePolicy",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource"
        ],
        Resource = aws_secretsmanager_secret.lambda_private_key.arn,
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = [var.lambda_role_arn,var.oidc_role_arn]
          }
        }
      },

      # Allow Lambda read
      {
        Sid    = "AllowLambdaRead",
        Effect = "Allow",
        Principal = {
          AWS = var.lambda_role_arn
        },
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = aws_secretsmanager_secret.lambda_private_key.arn
      },

      # Allow OIDC role manage + read
      {
        Sid    = "AllowOidcManage",
        Effect = "Allow",
        Principal = {
          AWS = var.oidc_role_arn
        },
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:RestoreSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:RotateSecret",
          "secretsmanager:CancelRotateSecret",
          "secretsmanager:PutResourcePolicy",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource"
        ],
        Resource = aws_secretsmanager_secret.lambda_private_key.arn
      }
    ]
  })
}
