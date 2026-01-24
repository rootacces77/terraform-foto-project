data "aws_organizations_organization" "organization" {}

locals {
    org_id      = data.aws_organizations_organization.organization.id
}