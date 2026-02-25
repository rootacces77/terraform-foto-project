output "lambda_role_arn" {
    value = aws_iam_role.lambda_exec.arn
  
}

output "lambda_cookie_generator_name" {
    value = aws_lambda_function.cookie_generator.function_name
  
}

output "lambda_cookie_generator_arn" {
    value = aws_lambda_function.cookie_generator.arn
  
}

output "lambda_thumb_arn" {
    value = aws_lambda_function.thumb_generator.arn
  
}