terraform {
  required_version = ">= 1.13.3, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.44.0"
    }
    random = { source = "hashicorp/random", version = "3.7.2"
    }

  }
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = var.name, ManagedBy = "Terraform", Purpose = "BurstLab" }
  }
}
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_caller_identity" "current" {
}
data "aws_partition" "current" {
}
locals {
  services = { service-a = 8080, service-b = 8081, worker = 8082
  }
  apps = var.deploy_apps ? local.services : {}
}
