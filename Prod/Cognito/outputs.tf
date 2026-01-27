output "cognito_issuer" {
    value = local.cognito_issuer

}

output "cognito_user_pool_client_id" {
    value = aws_cognito_user_pool_client.admin_spa.id
  
}