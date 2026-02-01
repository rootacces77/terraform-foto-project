resource "aws_organizations_policy" "deny_non_us_east_1" {
  name        = "AllowRegions"
  description = "Deny actions outside us-east-1; exclude global services."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid    = "DenyOutsideUsEast1",
        Effect = "Deny",
        NotAction = [
          # Global / edge or special endpoints to exclude from region checks
          "a2c:*",                    # Account/alternate contacts (varies)
          "budgets:*",
          "ce:*",
          "cloudfront:*",
          "globalaccelerator:*",
          "iam:*",
          "organizations:*",
          "route53:*",
          "route53domains:*",
          "sso:*",
          "sso-directory:*",
          "support:*",
          "waf:*",
          "waf-regional:*",
          "wafv2:*",
          "shield:*",
          "health:*",
          "networkmanager:*",
          "account:*"
        ],
        Resource  = "*",
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" : [ "us-east-1","eu-south-1" ]
          }
        }
      }
    ]
  })
}

data "aws_organizations_organization" "organization" {}

locals {
    org_root_id = data.aws_organizations_organization.organization.roots[0].id
}


resource "aws_organizations_policy_attachment" "attach_region_restriction" {
  policy_id = aws_organizations_policy.deny_non_us_east_1.id
  target_id = local.org_root_id
}



