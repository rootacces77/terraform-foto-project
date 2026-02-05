
variable "share_links_table_name" {
  type        = string
  description = "DynamoDB table name for share links"
  default     = "GalleryShareLinks"
}

variable "enable_share_links_folder_gsi" {
  type        = bool
  description = "Enable GSI on 'folder' to list links per folder from admin UI"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}