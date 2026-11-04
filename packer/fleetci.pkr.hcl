# fleetci class images: Ubuntu 24.04 with Docker and actions/runner, for
# fleetci.classes[*].ami_id. One AMI per architecture; every class of that
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
  description = "actions/runner release to unpack; keep fleetci.github_runner_version equal to it"
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
}

build {
  sources = [
    "source.amazon-ebs.ubuntu-amd64",
    "source.amazon-ebs.ubuntu-arm64",
  ]

  provisioner "shell" {
    script          = "${path.root}/fleetci-vm.sh"
    execute_command = "sudo -E bash '{{ .Path }}'"
    environment_vars = [
      "RUNNER_USER=ubuntu",
      "RUNNER_VERSION=${var.runner_version}",
      "RUNNER_ARCH=${source.name == "ubuntu-arm64" ? "arm64" : "x64"}",
    ]
  }
}
