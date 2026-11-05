#!/bin/bash
# Provisions a fleetci class image: Ubuntu with Docker, like GitHub's
# ubuntu-latest, and actions/runner unpacked so GitHub jobs don't download
# it. Run by fleetci.pkr.hcl, beside it, with RUNNER_USER, RUNNER_VERSION and RUNNER_ARCH.
#
# Class VMs have no instance profile, so their metadata holds no
# credentials; the DOCKER-USER rule still keeps job containers from it.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Ubuntu's first-boot apt run holds the lock for a while.
cloud-init status --wait >/dev/null || true

apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q --no-install-recommends docker.io docker-buildx iptables libicu74 git zstd curl ca-certificates ec2-instance-connect
usermod -aG docker "$RUNNER_USER"

mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/no-imds.conf <<'UNIT'
[Service]
ExecStartPost=/usr/sbin/iptables -I DOCKER-USER -d 169.254.169.254 -j DROP
UNIT
systemctl daemon-reload
systemctl enable docker

runner_dir="/home/$RUNNER_USER/actions-runner-$RUNNER_VERSION"
install -d -o "$RUNNER_USER" -g "$RUNNER_USER" "$runner_dir"
curl -fsSL --retry 5 "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-$RUNNER_ARCH-$RUNNER_VERSION.tar.gz" |
  sudo -u "$RUNNER_USER" tar -xz -C "$runner_dir"

apt-get clean
rm -rf /var/lib/apt/lists/*
