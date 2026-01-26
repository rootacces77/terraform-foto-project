output "signer_api_execute_arn" {
    value = "${aws_apigatewayv2_api.signer.execution_arn}/${aws_apigatewayv2_stage.prod.name}/POST/sign"
  
}