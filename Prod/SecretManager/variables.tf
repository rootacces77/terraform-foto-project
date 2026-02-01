variable "lambda_role_arn" {
     type = string
     description = "Lambda Role ARN"
}


variable "oidc_role_name" {
  type        = string
  description = "Name of the existing OIDC IAM role (e.g., GitHubActionsOIDCRole)."
  default = "GitHubActionsTerraformRole"
}

variable "oidc_role_arn" {
  type = string
  default = "arn:aws:iam::238407199949:role/GitHubActionsTerraformRole"
  
}

data "aws_iam_role" "oidc" {
  name = var.oidc_role_name
}
