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

locals {
    timestamp = regex_replace(timestamp(), "[- TZ:]", "")
    name = "gitlab-runner-${local.timestamp}"
}

source "amazon-ebs" "amazon-linux-x86_64" {
  ami_name      = format("%s-%s", local.name, "amazon-linux-x86_64")
  instance_type = "t2.nano"
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-x86_64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true

    owners = ["137112412989"] # Amazon Linux 2 AMI owner ID
  }
  ssh_username = "ec2-user"
}

source "amazon-ebs" "amazon-linux-arm64" {
  ami_name      = format("%s-%s", local.name, "amazon-linux-arm64")
  instance_type = "t4g.nano"
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "amzn2-ami-hvm-*-arm64-gp2"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true

    owners = ["137112412989"] # Amazon Linux 2 AMI owner ID
  }
  ssh_username = "ec2-user"
}

# a build block invokes sources and runs provisioning steps on them.
build {
  sources = [
    "source.amazon-ebs.amazon-linux-x86_64",
    "source.amazon-ebs.amazon-linux-arm64",
  ]

  provisioner "shell" {
    inline = [
      "sudo yum update -y",
      "sudo yum install -y docker",
      "sudo usermod -a -G docker ec2-user",
      "sudo systemctl enable docker",
    ]
  }
}
