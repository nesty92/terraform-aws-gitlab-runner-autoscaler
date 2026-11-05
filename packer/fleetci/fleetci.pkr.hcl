# fleetci class images: Ubuntu 24.04 with Docker and actions/runner, for
# a fleetci runner's own AMI and its classes' ami_id. One AMI per architecture; every class of that
# architecture can use it.
packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID where the builder will launch the instance"
}

variable "subnet_id" {
  type        = string
  description = "The Subnet ID where the builder will launch the instance"
}

variable "runner_version" {
  type        = string
  default     = "2.338.2"
  description = "actions/runner release to unpack; keep the runner's fleetci github_runner_version equal to it"
}

variable "associate_public_ip_address" {
  type        = bool
  default     = null
  description = "true gives the builder a public IPv4, for a public subnet that does not assign one; unset follows the subnet"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags for the AMI and its snapshot, such as a cost allocation tag"
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  name      = "fleetci-${local.timestamp}"
}

source "amazon-ebs" "ubuntu-amd64" {
  ami_name      = format("%s-%s", local.name, "ubuntu-24.04-amd64")
  instance_type = "t3.small"
  region        = var.region
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
  ssh_username = "ubuntu"

  associate_public_ip_address = var.associate_public_ip_address
  # Packer's temporary security group admits SSH from the builder's own
  # address only, not from anywhere.
  temporary_security_group_source_public_ip = true

  tags          = merge({ Name = local.name }, var.tags)
  snapshot_tags = merge({ Name = local.name }, var.tags)
}

source "amazon-ebs" "ubuntu-arm64" {
  ami_name      = format("%s-%s", local.name, "ubuntu-24.04-arm64")
  instance_type = "t4g.small"
  region        = var.region
  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical
  }
  ssh_username = "ubuntu"

  associate_public_ip_address = var.associate_public_ip_address
  # Packer's temporary security group admits SSH from the builder's own
  # address only, not from anywhere.
  temporary_security_group_source_public_ip = true

  tags          = merge({ Name = local.name }, var.tags)
  snapshot_tags = merge({ Name = local.name }, var.tags)
}

build {
  sources = [
    "source.amazon-ebs.ubuntu-amd64",
    "source.amazon-ebs.ubuntu-arm64",
  ]

  provisioner "shell" {
    script = "${path.root}/fleetci-vm.sh"
    # {{ .Vars }} carries environment_vars; without it the script sees none.
    execute_command = "sudo {{ .Vars }} bash '{{ .Path }}'"
    environment_vars = [
      "RUNNER_USER=ubuntu",
      "RUNNER_VERSION=${var.runner_version}",
      "RUNNER_ARCH=${source.name == "ubuntu-arm64" ? "arm64" : "x64"}",
    ]
  }
}
