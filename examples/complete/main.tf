# This file provides an example usage of the Terraform module.
data "aws_availability_zones" "available" {}

# Define the provider configuration
provider "aws" {
  region = var.region
}

locals {
  architectures = ["amd64", "arm64"]
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "vpc-${var.environment}"
  cidr = "10.0.0.0/16"

  azs                     = [data.aws_availability_zones.available.names[0]]
  private_subnets         = ["10.0.1.0/24"]
  public_subnets          = ["10.0.101.0/24"]
  map_public_ip_on_launch = false

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = var.environment
  }
}

module "aws-gitlab-runners-spot-autoscaler" {
  source = "../../"

  fleeting_plugin_aws_version = var.fleeting_plugin_aws_version
  gitlab_runner_version       = var.gitlab_runner_version

  aws_vpc_id     = module.vpc.vpc_id
  aws_azs        = module.vpc.azs
  aws_subnet_ids = module.vpc.private_subnets

  architectures = local.architectures

  environment = "test"

  runner_ssm_token_amd64 = {
    name   = try(aws_ssm_parameter.runner_registration_token["amd64"].name, null)
    arn    = try(aws_ssm_parameter.runner_registration_token["amd64"].arn, null)
    region = var.region
  }
  runner_ssm_token_arm64 = {
    name   = try(aws_ssm_parameter.runner_registration_token["arm64"].name, null)
    arn    = try(aws_ssm_parameter.runner_registration_token["arm64"].arn, null)
    region = var.region
  }

  runner_instance_amd64 = {
    name_prefix = "gitlab-runner-amd64"
    ami_id      = var.runner_amd64_ami_id
  }

  runner_instance_arm64 = {
    name_prefix = "gitlab-runner-arm64"
    ami_id      = var.runner_arm64_ami_id
  }
}

resource "aws_ssm_parameter" "runner_registration_token" {
  for_each = toset(local.architectures)

  name  = format("gitlab-runner-%s-token", each.key)
  type  = "SecureString"
  value = "null"

  lifecycle {
    ignore_changes = [value]
  }
}
