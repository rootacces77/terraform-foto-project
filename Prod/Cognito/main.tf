data "aws_region" "current" {}

############################################
# Cognito User Pool
############################################
resource "aws_cognito_user_pool" "admin" {
  name = "admin-user-pool"

  # Keep simple; adjust to your preference
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
  }

  # Optional: basic account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

############################################
# Cognito User Pool App Client (SPA / Static page)
# - No client secret
# - Authorization Code flow (PKCE in frontend)
############################################
resource "aws_cognito_user_pool_client" "admin_spa" {
  name         = "admin-spa-client"
  user_pool_id = aws_cognito_user_pool.admin.id

  generate_secret = false

  # Hosted UI / OAuth settings
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"] # Authorization Code flow
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [var.cognito_callback_urls]
  logout_urls   = [var.cognito_logout_urls]

  # Token validity (optional tuning)
  access_token_validity  = 60  # minutes
  id_token_validity      = 60  # minutes
  refresh_token_validity = 7   # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # Helps prevent user enumeration; optional
  prevent_user_existence_errors = "ENABLED"
}

############################################
# Cognito Hosted UI domain
# This creates: https://<prefix>.auth.<region>.amazoncognito.com
############################################
resource "aws_cognito_user_pool_domain" "admin_domain" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.admin.id
}

############################################
# Issuer URL for JWT authorizer
############################################
locals {
  cognito_issuer = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.admin.id}"
}

