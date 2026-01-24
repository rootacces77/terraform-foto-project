############################################################
# Permission Set: Allow only execute-api:Invoke on signer API
############################################################
resource "aws_ssoadmin_permission_set" "signer_invoke" {
  instance_arn     = local.sso_instance_arn
  name             = "photo-signer-invoke"
  description      = "Allows invoking the signer API to generate CloudFront signed cookies."
  session_duration = "PT4H" # adjust as desired (e.g., PT1H, PT8H)
}

data "aws_iam_policy_document" "signer_invoke" {
  statement {
    sid     = "AllowInvokeSignerApi"
    effect  = "Allow"
    actions = ["execute-api:Invoke"]
    resources = [var.signer_api_execute_arn]
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "signer_invoke" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.signer_invoke.arn
  inline_policy      = data.aws_iam_policy_document.signer_invoke.json
}

############################################################
# Assign permission set to the user in the target account
############################################################
resource "aws_ssoadmin_account_assignment" "signer_admin_assignment" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.signer_invoke.arn

  principal_id   = aws_identitystore_user.signer_admin.user_id
  principal_type = "USER"

  target_id   = var.target_account_id
  target_type = "AWS_ACCOUNT"
}