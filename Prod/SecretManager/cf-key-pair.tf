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
      ############################################
      # 1) DENY for anyone who is not Lambda or OIDC
      #    - covers read + management on THIS secret
      ############################################
      {
        Sid       = "DenySecretAccessUnlessLambdaOrOidc",
        Effect    = "Deny",
        Principal = "*",
        Action = [
          # Read
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",

          # Manage this secret
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
          StringNotEquals = {
            "aws:PrincipalArn" = [
              var.lambda_role_arn,
              data.aws_iam_role.oidc.arn
            ]
          }
        }
      },

      ############################################
      # 2) Explicit ALLOW: Lambda role can read
      ############################################
      {
        Sid    = "AllowLambdaReadSecret",
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

      ############################################
      # 3) Explicit ALLOW: OIDC role can manage + read
      ############################################
      {
        Sid    = "AllowOidcManageSecret",
        Effect = "Allow",
        Principal = {
          AWS = data.aws_iam_role.oidc.arn
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
