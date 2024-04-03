variable "region" {
  description = "The AWS region to deploy the GitLab Runner to."
  default     = "us-west-2"
}

variable "environment" {
  description = "The environment to deploy the GitLab Runner to."
  default     = "test"
}

variable "runner_token_amd64" {
  description = "The autehntication token for the GitLab Runner registration token for amd64 instances."
  type        = string
  sensitive   = true
}

variable "runner_token_arm64" {
  description = "The autehntication token for the GitLab Runner registration token for arm64 instances."
  type        = string
  sensitive   = true
}

variable "fleeting_plugin_aws_version" {
  description = "The version of the AWS Fleeting plugin to install."
  type        = string
}

variable "gitlab_runner_version" {
  description = "The version of the GitLab Runner to install."
  type        = string
}
