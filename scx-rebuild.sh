#!/usr/bin/env bash
# Pull latest main, rebuild, reinstall. Run from anywhere.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"
git pull --ff-only
cargo build --release
sudo "$REPO_DIR/scx-install.sh"
