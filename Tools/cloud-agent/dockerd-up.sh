#!/usr/bin/env bash
# Bring up the Docker daemon inside the Cloud Agent VM and make it usable.
#
# The VM is a nested container without systemd as PID 1, so dockerd is started
# by hand. Two nested-container quirks are handled here:
#   * overlay2 cannot mount on top of the VM's own overlay root, so the daemon
#     is configured (in install) to use the fuse-overlayfs storage driver.
#   * Docker turns on net.bridge.bridge-nf-call-iptables, which sends same-bridge
#     L2 traffic through the FORWARD chain where the nft ruleset drops it. That
#     breaks container-to-container connections (e.g. storage-api -> postgres).
#     Turning it off lets containers on a bridge talk to each other directly.
set -euo pipefail

if ! sudo docker info >/dev/null 2>&1; then
  sudo bash -c 'nohup dockerd >/var/log/dockerd.log 2>&1 &'
  for _ in $(seq 1 60); do
    sudo docker info >/dev/null 2>&1 && break
    sleep 1
  done
fi

sudo sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>&1 || true
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>&1 || true
sudo chmod 666 /var/run/docker.sock || true

sudo docker info >/dev/null 2>&1 && echo "dockerd is up" || { echo "dockerd failed to start" >&2; exit 1; }
