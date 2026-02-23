terraform {
  backend "s3" {
    bucket         = "tf-state-project-practice77"
    key            = "Prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  alias = "us-east-1"
  region = "us-east-1"

}

provider "aws" {
  alias = "eu-south-1"
  region = "eu-south-1"

}