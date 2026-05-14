#!/usr/bin/env bash
# Revert: remove scx binaries installed by scx-install.sh from /usr/local/bin,
# leaving the pacman-managed copies in /usr/bin as the active version.
set -euo pipefail

MANIFEST_DIR="/usr/local/share/scx-from-source"
MANIFEST="$MANIFEST_DIR/MANIFEST"

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (use: sudo $0)" >&2
    exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "no manifest at $MANIFEST — nothing to revert" >&2
    exit 0
fi

removed=0
while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    if [[ -e "$path" ]]; then
        rm -f -- "$path"
        echo "removed: $path"
        removed=$((removed + 1))
    fi
done < "$MANIFEST"

rm -f -- "$MANIFEST" "$MANIFEST.meta"
rmdir --ignore-fail-on-non-empty "$MANIFEST_DIR" 2>/dev/null || true

# Restart scx_loader so it re-resolves scheduler paths via PATH and
# finds the pacman binaries in /usr/bin.
if systemctl is-active --quiet scx_loader.service; then
    systemctl restart scx_loader.service
    echo "restarted: scx_loader.service"
fi

# Sanity-check: the pacman files should now be the active ones.
echo
echo "Reverted $removed file(s). Active scx_rusty is now:"
command -v scx_rusty || echo "  (scx_rusty not in PATH — is scx-scheds installed? sudo pacman -S scx-scheds)"

# Offer a hint if pacman's files are missing for some reason.
if ! pacman -Qkk scx-scheds >/dev/null 2>&1; then
    echo
    echo "note: 'pacman -Qkk scx-scheds' reports modifications;"
    echo "      to fully restore from pacman, run:"
    echo "        sudo pacman -S scx-scheds scx-tools"
fi
