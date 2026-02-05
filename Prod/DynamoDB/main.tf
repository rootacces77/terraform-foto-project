resource "aws_dynamodb_table" "share_links" {
  name         = var.share_links_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "link_token"

  attribute {
    name = "link_token"
    type = "S"
  }

  # GSI partition key attribute
  attribute {
    name = "folder"
    type = "S"
  }

  # TTL attribute (Epoch seconds). DynamoDB will delete items automatically after TTL.
  ttl {
    attribute_name = "ttl_epoch"
    enabled        = true
  }

  # Query links by folder (admin "show active links for folder")
  global_secondary_index {
    name            = "gsi_folder"
    hash_key        = "folder"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = var.tags
}