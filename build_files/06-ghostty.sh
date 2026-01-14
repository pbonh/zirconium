#!/bin/bash
set -ouex pipefail

# Determine releasever dynamically (e.g., Fedora 43)
releasever="${releasever:-}"
if [[ -z "${releasever}" ]]; then
	releasever="$(rpm -E %fedora 2>/dev/null || true)"
fi
if [[ -z "${releasever}" ]]; then
	releasever="$(rpm -E %rhel 2>/dev/null || true)"
fi
if [[ -z "${releasever}" && -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	releasever="${VERSION_ID:-}"
fi
if [[ -z "${releasever}" ]]; then
	echo "releasever is unset and could not be determined" >&2
	exit 1
fi
export releasever

# --- Ghostty via Terra (Fyralabs) repo/package ---
# Ghostty docs (Fedora -> Terra) install terra-release from Terra repo path, then install ghostty. :contentReference[oaicite:1]{index=1}

# 1) Add Terra repo by installing terra-release (initial install uses --nogpgcheck per docs) :contentReference[oaicite:2]{index=2}
dnf5 install -y \
  --nogpgcheck \
  --repofrompath="terra,https://repos.fyralabs.com/terra$releasever" \
  terra-release

# 2) Install Ghostty :contentReference[oaicite:3]{index=3}
dnf5 install -y ghostty

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true

