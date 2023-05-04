terraform {
  required_version = ">= 1.2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  cloud {
    organization = "colanderapp"

    workspaces {
      name = "colander-app-dev"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
