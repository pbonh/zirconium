#!/bin/bash
set -ouex pipefail

# --- Cursor via upstream RPM (x86_64/aarch64) ---
# Cursor publishes architecture-specific RPMs at stable URLs.
# x86_64: https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/2.3
# aarch64: https://api2.cursor.sh/updates/download/golden/linux-arm64-rpm/cursor/2.3

# Ensure required tools
dnf5 install -y curl coreutils

# Detect architecture and select URL
arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64)
    CURSOR_RPM_URL="https://api2.cursor.sh/updates/download/golden/linux-x64-rpm/cursor/2.3"
    ;;
  aarch64|arm64)
    CURSOR_RPM_URL="https://api2.cursor.sh/updates/download/golden/linux-arm64-rpm/cursor/2.3"
    ;;
  *)
    echo "Unsupported architecture '${arch}'. Supported: x86_64, aarch64" >&2
    exit 1
    ;;
esac

CURSOR_RPM_PATH="/tmp/cursor.rpm"

# Download RPM
curl -fsSL "${CURSOR_RPM_URL}" -o "${CURSOR_RPM_PATH}"

# Install RPM
dnf5 install -y "${CURSOR_RPM_PATH}"

# Cleanup
rm -f "${CURSOR_RPM_PATH}"
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
