#!/usr/bin/env bash
set -euo pipefail

# Classify every file under mkosi.conf.d, mkosi.extra, repos, assets as one of:
#   INHERITED      — identical to upstream
#   USER-OVERRIDE  — present in upstream but modified
#   USER-ADDED     — not present in upstream

UPSTREAM=${1:-/tmp/zirconium-upstream}
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ ! -d "$UPSTREAM" ]; then
    echo "Upstream clone not found at $UPSTREAM" >&2
    exit 1
fi

UPSTREAM_COMMIT=$(git -C "$UPSTREAM" rev-parse HEAD)
echo "# Audit against upstream commit: $UPSTREAM_COMMIT"
echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

for dir in mkosi.conf.d mkosi.extra repos assets; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' f; do
        upstream_f="$UPSTREAM/$f"
        if [ ! -e "$upstream_f" ]; then
            echo "USER-ADDED: $f"
        elif [ -f "$f" ] && [ -f "$upstream_f" ]; then
            if cmp -s "$f" "$upstream_f"; then
                echo "INHERITED: $f"
            else
                echo "USER-OVERRIDE: $f"
            fi
        elif [ -L "$f" ]; then
            echo "SYMLINK: $f -> $(readlink "$f")"
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
done

echo
echo "# Summary"
