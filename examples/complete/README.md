This example deploys a GitLab Runner to AWS using spot instances. The runner is configured to use the AWS Fleeting plugin to manage the spot instances.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_aws-gitlab-runners-spot-autoscaler"></a> [aws-gitlab-runners-spot-autoscaler](#module\_aws-gitlab-runners-spot-autoscaler) | ../../ | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_ssm_parameter.runner_registration_token](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | The environment to deploy the GitLab Runner to. | `string` | `"test"` | no |
| <a name="input_fleeting_plugin_aws_version"></a> [fleeting\_plugin\_aws\_version](#input\_fleeting\_plugin\_aws\_version) | The version of the AWS Fleeting plugin to install. | `string` | n/a | yes |
| <a name="input_gitlab_runner_version"></a> [gitlab\_runner\_version](#input\_gitlab\_runner\_version) | The version of the GitLab Runner to install. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The AWS region to deploy the GitLab Runner to. | `string` | `"us-west-2"` | no |
| <a name="input_runner_amd64_ami_id"></a> [runner\_amd64\_ami\_id](#input\_runner\_amd64\_ami\_id) | The AMI ID to use for the AMD64 GitLab Runner instances. | `string` | n/a | yes |
| <a name="input_runner_arm64_ami_id"></a> [runner\_arm64\_ami\_id](#input\_runner\_arm64\_ami\_id) | The AMI ID to use for the ARM64 GitLab Runner instances. | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->