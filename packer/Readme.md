# Packer Configuration

This directory contains the Packer configuration for building GitLab Runner AMIs. The build creates Amazon Linux 2 AMIs with Docker pre-installed and configured for both AMD64 and ARM64 architectures.

## AMI Requirements

The built AMIs meet the following specifications required by the Terraform module:

- **Operating System**: Amazon Linux 2 (amzn2-ami-hvm)
- **Architecture**: Separate AMIs for x86_64 (AMD64) and arm64 (ARM64)
- **Docker**: Installed, enabled, and configured to start on boot
- **User**: `ec2-user` with Docker group membership
- **Virtualization**: HVM virtualization type
- **Root Device**: EBS-backed storage

## Prerequisites

- Packer (version 1.6.6 or later)
- AWS account with permissions to create EC2 instances and AMIs
- VPC and subnet for the Packer builder instance

## Usage

**Build both AMD64 and ARM64 AMIs**:

```bash
cd packer
packer init .
packer build \
  -var="vpc_id=vpc-xxxxx" \
  -var="subnet_id=subnet-xxxxx" \
  -var="region=us-west-2" \
  image.pkr.hcl
```

**Required variables**:
- `vpc_id`: VPC where the builder instance will launch
- `subnet_id`: Subnet where the builder instance will launch

**Optional variables**:
- `region`: AWS region for the build (default: `us-west-2`)

The build creates two AMIs:
- `gitlab-runner-{timestamp}-amazon-linux-x86_64`
- `gitlab-runner-{timestamp}-amazon-linux-arm64`

AMI IDs are displayed in the build output. Save these for your Terraform configuration.

## fleetci Class Images

`fleetci/fleetci.pkr.hcl` builds the images for fleetci pools: the pool's `ami_id` and `fleetci.classes[*].ami_id`: Ubuntu 24.04 (Canonical's) with Docker, libicu and actions/runner unpacked in `/home/ubuntu/actions-runner-<runner_version>`, for amd64 and arm64. `fleetci/fleetci-vm.sh` does the provisioning, and also keeps job containers away from instance metadata. It has a directory of its own because its variables share names with `image.pkr.hcl`'s, and `packer init .` reads every template in a directory.

```bash
cd packer/fleetci
packer init .
packer build \
  -var="vpc_id=vpc-xxxxx" \
  -var="subnet_id=subnet-xxxxx" \
  -var="region=us-west-2" \
  -var="runner_version=2.338.2" \
  .
```

Optional: `associate_public_ip_address = true` for a public subnet that assigns no public IPv4 (Packer connects over SSH from where it runs), `tags` for the AMI and its snapshot, and `-only=amazon-ebs.ubuntu-amd64` for one architecture. The builder's temporary security group admits SSH from the builder's own public address only.

It creates `fleetci-{timestamp}-ubuntu-24.04-amd64` and `fleetci-{timestamp}-ubuntu-24.04-arm64`. Every class of an architecture can share its image. Keep the pool's `fleetci.github_runner_version` equal to `runner_version`; otherwise each GitHub job downloads the runner.

## Important Notes

- **Architecture Alignment**: Provide an AMI for each architecture in your Terraform `architectures` variable. If using both `amd64` and `arm64`, you need both AMI IDs.
- **Regional AMIs**: AMI IDs are region-specific. For multi-region deployments, build AMIs in each region or copy them between regions.
- **Manual Creation**: You can manually create AMIs if needed, but they must meet all requirements listed above. Use this Packer configuration as a reference.

## Contributing

If you find any issues or have suggestions for improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the Apache 2.0 License. See the [LICENSE](../LICENSE) file for more details.