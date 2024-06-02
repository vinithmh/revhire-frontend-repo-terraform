terraform {
  backend "s3" {
    bucket         = "s3-revhire-frontend-bucket-remote-new"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "revhire-frontend-table-backend-dynamodb-new"
  }
}

