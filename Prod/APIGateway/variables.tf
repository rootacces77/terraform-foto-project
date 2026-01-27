variable "lambda_cookie_generator_arn" {
    type = string
    description = "Lambda cookie-generator function ARN"
  
}

variable "lambda_cookie_generator_name" {
    type = string
    description = "Lambda cookie-generator function NAME"
  
}

variable "cognito_issuer" {
    type = string
  
}

variable "cognito_user_pool_client_id" {
    type = string
  
}