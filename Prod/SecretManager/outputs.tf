output "secret_manager_pk_id" {
    value = aws_secretsmanager_secret.lambda_private_key.id
  
}

output "lambda_private_key_secret_arn" {
    value = aws_secretsmanager_secret.lambda_private_key.arn
  
}