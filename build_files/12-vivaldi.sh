#!/bin/bash
set -ouex pipefail

# --- Vivaldi browser via official RPM ---
VIVALDI_VERSION="${VIVALDI_VERSION:-7.8.3925.62-1}"

arch="$(uname -m)"
case "${arch}" in
x86_64 | amd64)
	vivaldi_arch="x86_64"
	;;
aarch64 | arm64)
	vivaldi_arch="aarch64"
	;;
*)
	echo "Unsupported architecture '${arch}'. Supported: x86_64, aarch64" >&2
	exit 1
	;;
esac

VIVALDI_RPM_URL_DEFAULT="https://downloads.vivaldi.com/stable/vivaldi-stable-${VIVALDI_VERSION}.${vivaldi_arch}.rpm"
VIVALDI_RPM_URL="${VIVALDI_RPM_URL:-${VIVALDI_RPM_URL_DEFAULT}}"
VIVALDI_RPM_PATH="/tmp/vivaldi-stable.rpm"

# Ensure tools exist
dnf5 install -y curl coreutils

# Download RPM
curl -fsSL "${VIVALDI_RPM_URL}" -o "${VIVALDI_RPM_PATH}"

# Install RPM
dnf5 install -y "${VIVALDI_RPM_PATH}"

# Cleanup
rm -f "${VIVALDI_RPM_PATH}"
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
