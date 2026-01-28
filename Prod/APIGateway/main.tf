############################################
# API Gateway (HTTP API v2)
############################################
resource "aws_apigatewayv2_api" "signer" {
  name          = "signer-api"
  protocol_type = "HTTP"


  cors_configuration {
    # Only allow your admin site to call the API from the browser
    allow_origins = [
      var.admin_origin
    ]

    # Your admin JS calls POST /sign, and the browser will preflight OPTIONS
    allow_methods = ["POST", "OPTIONS"]

    # Because you send JWT in Authorization and JSON payload
    allow_headers = ["authorization", "content-type"]

    # Optional: cache preflight responses (seconds)
    max_age = 3600

    # You are NOT using browser cookies to call the API, so keep this false/omitted
    # allow_credentials = false
  }
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
# API Gateway HTTP API JWT Authorizer
############################################
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.signer.id
  name             = "cognito-jwt-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.cognito_issuer
    audience = [var.cognito_user_pool_client_id]
  }
}


############################################
# Route: POST /sign  (JWT protected)
############################################
resource "aws_apigatewayv2_route" "sign" {
  api_id    = aws_apigatewayv2_api.signer.id
  route_key = "POST /sign"
  target    = "integrations/${aws_apigatewayv2_integration.signer_lambda.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id

}

############################################
# Route: GET /open 
############################################
resource "aws_apigatewayv2_route" "open" {
  api_id    = aws_apigatewayv2_api.signer.id
  route_key = "GET /open"
  target    = "integrations/${aws_apigatewayv2_integration.signer_lambda.id}"

  authorization_type = "NONE"
}

############################################
# Route: GET /list
############################################
resource "aws_apigatewayv2_route" "list" {
  api_id    = aws_apigatewayv2_api.signer.id
  route_key = "GET /list"
  target    = "integrations/${aws_apigatewayv2_integration.signer_lambda.id}"

  authorization_type = "NONE"
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

resource "aws_lambda_permission" "allow_apigw_invoke_open" {
  statement_id  = "AllowExecutionFromAPIGatewayV2Open"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_cookie_generator_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.signer.execution_arn}/${aws_apigatewayv2_stage.prod.name}/GET/open"
}

resource "aws_lambda_permission" "allow_apigw_invoke_list" {
  statement_id  = "AllowExecutionFromAPIGatewayV2Openx"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_cookie_generator_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.signer.execution_arn}/${aws_apigatewayv2_stage.prod.name}/GET/list"
}

