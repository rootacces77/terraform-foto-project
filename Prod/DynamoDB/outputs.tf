
output "dynamodb_table_name" {
  value = aws_dynamodb_table.share_links.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.share_links.arn
}