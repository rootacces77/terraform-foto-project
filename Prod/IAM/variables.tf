variable "identity_center_user_email" {
  description = "Email for the Identity Center admin user."
  type        = string
}

variable "identity_center_user_given_name" {
  description = "Given name for the Identity Center admin user."
  type        = string
  default     = "Admin"
}

variable "identity_center_user_family_name" {
  description = "Family name for the Identity Center admin user."
  type        = string
  default     = "Signer"
}

variable "target_account_id" {
  description = "AWS Account ID where the Permission Set will be assigned."
  type        = string
}

variable "signer_api_execute_arn" {
  description = <<EOF
Execute API ARN for the signer API method(s) that the admin is allowed to invoke.

Examples:
- Tight (single method/resource):
  arn:aws:execute-api:eu-central-1:123456789012:abc123def4/prod/POST/sign

- Stage-wide (all methods/paths in a stage):
  arn:aws:execute-api:eu-central-1:123456789012:abc123def4/prod/*/*

Use the tightest ARN that matches your design.
EOF
  type = string
}