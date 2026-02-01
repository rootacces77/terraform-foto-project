variable "lambda_role_arn" {
     type = string
     description = "Lambda Role ARN"
}


variable "oidc_role_name" {
  type        = string
  description = "Name of the existing OIDC IAM role (e.g., GitHubActionsOIDCRole)."
  default = "GitHubActionsTerraformRole"
}

data "aws_iam_role" "oidc" {
  name = var.oidc_role_name
}
