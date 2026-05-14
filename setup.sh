#!/usr/bin/env bash
# setup.sh — bootstrap for scx-switch.
#
# What it does:
#   1. Clones sched-ext/scx to $SCX_REPO_DIR (default ~/src/scx) if not present.
#   2. Builds it with `cargo build --release` (uses cached artifacts if present).
#   3. Installs the built scheduler binaries to /usr/local/bin (sudo).
#   4. Installs the scx-switch CLI + helpers to /usr/local/sbin (sudo).
#
# What it does NOT do:
#   - Install build dependencies (rust, clang, libbpf, pahole, etc.).
#     See README.md "Requirements" for the per-distro command.
#   - Pick a scheduler. After this completes, run:
#       sudo scx-switch repo scx_flow      (or any other scheduler)
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SCX_REPO_DIR="${SCX_REPO_DIR:-$HOME/src/scx}"
SCX_REMOTE="${SCX_REMOTE:-https://github.com/sched-ext/scx}"
SBIN_DEST="/usr/local/sbin"

step() { printf '\n\033[1;36m── %s ──\033[0m\n' "$1"; }
note() { printf '   %s\n' "$1"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# ---------- Sanity checks ----------
step "Checking environment"

[[ -d /sys/kernel/sched_ext ]] || die "kernel lacks sched_ext support (need CONFIG_SCHED_CLASS_EXT=y)"
note "kernel: sched_ext available"

for cmd in git cargo rustc clang bpftool pkg-config; do
    command -v "$cmd" >/dev/null 2>&1 || die "missing build dep: $cmd — see README.md Requirements"
done
note "build deps: present"

# ---------- Clone (or update) scx source ----------
step "Preparing scx source at $SCX_REPO_DIR"

if [[ -d "$SCX_REPO_DIR/.git" ]]; then
    note "already cloned — running git pull"
    git -C "$SCX_REPO_DIR" pull --ff-only
else
    mkdir -p "$(dirname "$SCX_REPO_DIR")"
    git clone --depth=1 "$SCX_REMOTE" "$SCX_REPO_DIR"
fi

# ---------- Build ----------
step "Building (cargo build --release)"
note "this can take 5–15 min on a cold build"
(cd "$SCX_REPO_DIR" && cargo build --release)

# ---------- Stage helpers next to the source ----------
# scx-switch's `update` subcommand expects scx-install.sh and scx-revert.sh
# next to the scx source tree, so it can invoke them after `git pull`.
step "Staging install helpers in $SCX_REPO_DIR"
for f in scx-install.sh scx-revert.sh scx-rebuild.sh; do
    install -m 0755 "$SELF_DIR/$f" "$SCX_REPO_DIR/$f"
    note "$SCX_REPO_DIR/$f"
done

# ---------- Install binaries to /usr/local/bin ----------
step "Installing scheduler binaries to /usr/local/bin (sudo)"
sudo "$SCX_REPO_DIR/scx-install.sh"

# ---------- Install scx-switch CLI ----------
# Only the CLI goes on PATH; helpers stay next to the source tree and
# are invoked through $SCX_REPO_DIR by scx-switch.
step "Installing scx-switch CLI to $SBIN_DEST (sudo)"
sudo install -d -m 0755 "$SBIN_DEST"
sudo install -m 0755 "$SELF_DIR/scx-switch" "$SBIN_DEST/scx-switch"
note "installed: $SBIN_DEST/scx-switch"

# ---------- Done ----------
step "Done"
cat <<EOF
Next step — pick a scheduler:

  sudo scx-switch repo scx_flow       # use upstream-built scx_flow, persistent
  sudo scx-switch pacman scx_rusty    # use the distro version of scx_rusty
  scx-switch status                   # see what's currently active

Source tree:    $SCX_REPO_DIR
CLI installed:  $SBIN_DEST/scx-switch
EOF
