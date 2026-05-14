#!/usr/bin/env bash
# Install scx schedulers built from this repo into /usr/local/bin,
# shadowing the pacman-managed binaries in /usr/bin.
# A manifest is written to /usr/local/share/scx-from-source/MANIFEST
# so scx-revert.sh can remove exactly what was installed.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/target/release"
DEST_BIN="/usr/local/bin"
MANIFEST_DIR="/usr/local/share/scx-from-source"
MANIFEST="$MANIFEST_DIR/MANIFEST"

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (use: sudo $0)" >&2
    exit 1
fi

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "error: $BUILD_DIR not found — build first with: cargo build --release" >&2
    exit 1
fi

# Binaries to install: every scx_* scheduler plus the scxtop tool.
# Excludes test binaries (scx_arena_selftests) and build helpers (xtask).
BINS=()
while IFS= read -r f; do BINS+=("$f"); done < <(
    find "$BUILD_DIR" -maxdepth 1 -type f -executable -printf '%f\n' \
        | grep -E '^(scx_[a-z0-9]+|scxtop)$' \
        | grep -v '^scx_arena_selftests$' \
        | sort
)

if [[ ${#BINS[@]} -eq 0 ]]; then
    echo "error: no scx binaries found in $BUILD_DIR" >&2
    exit 1
fi

install -d -m 0755 "$DEST_BIN" "$MANIFEST_DIR"
: > "$MANIFEST"

for b in "${BINS[@]}"; do
    src="$BUILD_DIR/$b"
    dst="$DEST_BIN/$b"
    install -m 0755 "$src" "$dst"
    echo "$dst" >> "$MANIFEST"
    echo "installed: $dst"
done

# Record commit + timestamp for traceability.
{
    echo "# scx-from-source manifest"
    echo "# installed_at: $(date -Iseconds)"
    if git -C "$REPO_DIR" rev-parse HEAD >/dev/null 2>&1; then
        echo "# repo_commit: $(git -C "$REPO_DIR" rev-parse HEAD)"
    fi
} > "$MANIFEST.meta"

# Restart scx_loader so it picks up the new binaries on next scheduler load.
if systemctl is-active --quiet scx_loader.service; then
    systemctl restart scx_loader.service
    echo "restarted: scx_loader.service"
fi

echo
echo "Installed ${#BINS[@]} binaries to $DEST_BIN."
echo "Run scx-revert.sh to remove them and fall back to pacman versions."
