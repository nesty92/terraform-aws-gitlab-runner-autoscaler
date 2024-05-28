variable "region" {
  description = "The AWS region to deploy the GitLab Runner to."
  default     = "us-west-2"
}

variable "environment" {
  description = "The environment to deploy the GitLab Runner to."
  default     = "test"
}


variable "fleeting_plugin_aws_version" {
  description = "The version of the AWS Fleeting plugin to install."
  type        = string
}

variable "gitlab_runner_version" {
  description = "The version of the GitLab Runner to install."
  type        = string
}

variable "runner_amd64_ami_id" {
  description = "The AMI ID to use for the AMD64 GitLab Runner instances."
  type        = string
}

variable "runner_arm64_ami_id" {
  description = "The AMI ID to use for the ARM64 GitLab Runner instances."
  type        = string
}
