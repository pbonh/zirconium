#!/usr/bin/env bash
set -euo pipefail

# Installs three AI coding CLIs system-wide via npm.
# Versions are pinned to insulate against an upstream yank or a
# typosquat slipping through; bump them deliberately when you want
# to update.
#
# WARNING: bare-name `claude`, `codex`, and `pi` packages on npm
# are NOT the AI CLIs — they are unrelated/typosquat packages.
# Always use the scoped/owner-prefixed names below.

PACKAGES=(
    "@anthropic-ai/claude-code@2.1.123"
    "@openai/codex@0.125.0"
    "@mariozechner/pi-coding-agent@0.70.6"
)

command -v npm >/dev/null || { echo "npm not found; recipe 02 must install nodejs+npm" >&2; exit 1; }

for pkg in "${PACKAGES[@]}"; do
    echo "==> Installing $pkg"
    npm install -g --no-fund --no-audit "$pkg"
done

echo "==> Verifying binaries on PATH"
for bin in claude codex pi; do
    BIN_PATH=$(command -v "$bin") || { echo "Binary '$bin' not found after install" >&2; exit 1; }
    echo "    $bin -> $BIN_PATH"
done

echo "==> AI CLI installation complete"
