############################################################
# Discover IAM Identity Center instance + identity store
############################################################
data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

############################################################
# Create an Identity Center user (AWS-managed identity store)
############################################################
resource "aws_identitystore_user" "signer_admin" {
  identity_store_id = local.identity_store_id

  user_name = var.identity_center_user_email

  name {
    given_name  = var.identity_center_user_given_name
    family_name = var.identity_center_user_family_name
  }

  display_name = "Photo Signer Admin"

  emails {
    value   = var.identity_center_user_email
    primary = true
    type    = "work"
  }
}