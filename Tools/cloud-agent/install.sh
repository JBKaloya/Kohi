#!/usr/bin/env bash
# One-time (idempotent) setup for the Kohi Supabase backend in a Cloud Agent VM.
#
# The Kohi app itself is an iOS/SwiftUI target that only builds under Xcode on
# macOS, so it cannot run here. What *is* runnable on Linux is the backend the
# app talks to: the Postgres schema (supabase/migrations) and the Deno edge
# functions (supabase/functions). This installs everything needed to stand that
# backend up locally and warms the image cache so first boot is fast.
set -euo pipefail

SUPABASE_CLI_VERSION="2.117.0"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$DIR" rev-parse --show-toplevel)"

# 1. Docker engine (the Supabase local stack runs as containers).
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
fi

# 2. fuse-overlayfs: overlay2 cannot mount over the VM's overlay root.
#    Run non-interactively and keep existing conffiles (fuse3 prompts on
#    /etc/fuse.conf otherwise, which would hang/fail an unattended build).
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef \
  fuse-overlayfs

# 3. Point the daemon at fuse-overlayfs and allow the agent user to reach it.
sudo mkdir -p /etc/docker
echo '{"storage-driver":"fuse-overlayfs"}' | sudo tee /etc/docker/daemon.json >/dev/null
sudo groupadd -f docker
sudo usermod -aG docker "$(id -un)" || true

# 4. Supabase CLI (pinned).
if [ "$(supabase --version 2>/dev/null)" != "$SUPABASE_CLI_VERSION" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_linux_amd64.tar.gz" -o "$tmp/supabase.tar.gz"
  tar -xzf "$tmp/supabase.tar.gz" -C "$tmp"
  sudo install -m 0755 "$tmp/supabase" /usr/local/bin/supabase
  rm -rf "$tmp"
fi

# 5. Warm the Supabase container images (postgres, auth, storage, rest, studio,
#    edge runtime, ...) so they are captured in the snapshot and boot is quick.
#    This runs the full migration set once as a smoke test, then tears down.
"$DIR/dockerd-up.sh"
( cd "$REPO_ROOT" && supabase start && supabase stop --no-backup ) || true

echo "Kohi backend environment installed."
