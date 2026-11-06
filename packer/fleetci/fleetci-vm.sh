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
# Docker and the job cache on the instance's local NVMe, when it has one (the
# "d" types: c6id, c8id, m8id...). The disk is blank at every boot, so a unit
# formats and mounts it at /mnt/nvme before containerd and Docker start, and
# binds their data directories onto it; without one, both stay on the root
# volume. /mnt/nvme/cache is where a runner's docker volumes mount /cache from.
cat > /usr/local/sbin/fleetci-local-disk <<'SCRIPT'
#!/bin/bash
set -euo pipefail
mnt=/mnt/nvme
if ! mountpoint -q "$mnt"; then
  dev=""
  for block in /sys/block/nvme*n1; do
    [ -e "$block" ] || continue
    case "$(cat "$block/device/model" 2>/dev/null)" in
      *"Instance Storage"*) dev="/dev/$(basename "$block")"; break ;;
    esac
  done
  if [ -n "$dev" ]; then
    mkfs.ext4 -q -F -E nodiscard -L fleetci-local "$dev"
    mkdir -p "$mnt"
    mount -o noatime "$dev" "$mnt"
  fi
fi
mkdir -p "$mnt/cache"
if mountpoint -q "$mnt"; then
  for dir in docker containerd; do
    mkdir -p "$mnt/$dir" "/var/lib/$dir"
    mountpoint -q "/var/lib/$dir" || mount --bind "$mnt/$dir" "/var/lib/$dir"
  done
fi
SCRIPT
chmod 755 /usr/local/sbin/fleetci-local-disk
cat > /etc/systemd/system/fleetci-local-disk.service <<'UNIT'
[Unit]
Description=Docker and the job cache on the local NVMe disk, when there is one
After=local-fs.target
Before=containerd.service docker.service docker.socket

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/fleetci-local-disk

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable fleetci-local-disk docker

runner_dir="/home/$RUNNER_USER/actions-runner-$RUNNER_VERSION"
install -d -o "$RUNNER_USER" -g "$RUNNER_USER" "$runner_dir"
curl -fsSL --retry 5 "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-linux-$RUNNER_ARCH-$RUNNER_VERSION.tar.gz" |
  sudo -u "$RUNNER_USER" tar -xz -C "$runner_dir"

apt-get clean
rm -rf /var/lib/apt/lists/*
