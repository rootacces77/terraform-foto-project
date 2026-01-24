terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }

  required_version = ">= 1.2"
}

provider "aws" {
  region  = "eu-south-1"
  profile = "root"

  shared_config_files      = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
}