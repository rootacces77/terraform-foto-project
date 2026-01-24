############################################
# API Gateway (HTTP API v2)
############################################
resource "aws_apigatewayv2_api" "signer" {
  name          = "signer-api"
  protocol_type = "HTTP"
}

############################################
# Integration: API -> Lambda
############################################
resource "aws_apigatewayv2_integration" "signer_lambda" {
  api_id = aws_apigatewayv2_api.signer.id

  integration_type        = "AWS_PROXY"
  integration_uri         = var.lambda_cookie_generator_arn
  payload_format_version  = "2.0"
  timeout_milliseconds    = 10000
}

############################################
# Route: POST /sign  (IAM protected)
############################################
resource "aws_apigatewayv2_route" "sign" {
  api_id    = aws_apigatewayv2_api.signer.id
  route_key = "POST /sign"
  target    = "integrations/${aws_apigatewayv2_integration.signer_lambda.id}"

  authorization_type = "AWS_IAM"
}

############################################
# Stage
############################################
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.signer.id
  name        = "prod"
  auto_deploy = true

  # Optional: access logs
  # access_log_settings {
  #   destination_arn = aws_cloudwatch_log_group.api_access.arn
  #   format          = jsonencode({ requestId = "$context.requestId", status = "$context.status" })
  # }
}

############################################
# Allow API Gateway to invoke Lambda
############################################
resource "aws_lambda_permission" "allow_apigw_invoke" {
  statement_id  = "AllowExecutionFromAPIGatewayV2"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_cookie_generator_name
  principal     = "apigateway.amazonaws.com"

  # Restrict to this API + stage + method/path
  source_arn = "${aws_apigatewayv2_api.signer.execution_arn}/${aws_apigatewayv2_stage.prod.name}/POST/sign"
}