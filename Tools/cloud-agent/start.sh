#!/usr/bin/env bash
# Per-boot startup for the Kohi Supabase backend.
#
# Starts the Docker daemon (with the nested-container fixes) and brings the
# local Supabase stack up, applying every migration in supabase/migrations.
# Safe to run repeatedly: `supabase start` is a no-op when already running.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$DIR" rev-parse --show-toplevel)"

"$DIR/dockerd-up.sh"
cd "$REPO_ROOT"
supabase start

echo "Supabase is up. REST: http://127.0.0.1:54321  Studio: http://127.0.0.1:54323"
