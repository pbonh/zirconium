#!/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Ensure Terra repo is available (installed once in 03-extras)
ensure_terra_repo

# --- Zed via Terra (Fyralabs) repo/package ---
# Packages available per https://zed.dev/docs/linux under Fedora/Ultramarine (Terra)

zed_channel="${ZED_CHANNEL:-stable}"
case "${zed_channel}" in
stable)
	zed_pkg="zed"
	;;
preview)
	zed_pkg="zed-preview"
	;;
nightly)
	zed_pkg="zed-nightly"
	;;
*)
	echo "Unsupported ZED_CHANNEL: ${zed_channel}. Use stable|preview|nightly." >&2
	exit 1
	;;
esac

# Install Zed (stable/preview/nightly via ZED_CHANNEL)
dnf5 install -y "${zed_pkg}"

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
