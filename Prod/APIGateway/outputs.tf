output "signer_api_execute_arn" {
    value = "${aws_apigatewayv2_api.signer.execution_arn}/${aws_apigatewayv2_stage.prod.name}/POST/sign"
  
}

output "api_open_origin_domain_name" {
    value = replace(aws_apigatewayv2_api.signer.api_endpoint, "https://", "")
  
}