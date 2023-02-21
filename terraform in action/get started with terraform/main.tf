terraform {
  required_version = "~>1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.27"
    }
  }
}


provider "aws" {
  region = "us-east-1"
}


resource "aws_instance" "appinstance" {
  ami           = "ami-0dfcb1ef8550277af"
  instance_type = "t2.micro"
  tags = {
    environment = "development"
  }
}