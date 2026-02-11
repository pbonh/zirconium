#!/bin/bash
set -ouex pipefail

# --- Brave Browser via official RPM repo ---
# Channels: release | beta | nightly
BRAVE_CHANNEL="${BRAVE_CHANNEL:-release}"

case "${BRAVE_CHANNEL}" in
release)
	BRAVE_REPO_URL="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
	BRAVE_REPO_PATH="/etc/yum.repos.d/brave-browser.repo"
	BRAVE_REPO_ID="brave-browser"
	BRAVE_PKG="brave-browser"
	BRAVE_KEY_URL="https://brave-browser-rpm-release.s3.brave.com/brave-core.asc"
	BRAVE_KEY_PATH="/etc/pki/rpm-gpg/brave-core.asc"
	;;
beta)
	BRAVE_REPO_URL="https://brave-browser-rpm-beta.s3.brave.com/brave-browser-beta.repo"
	BRAVE_REPO_PATH="/etc/yum.repos.d/brave-browser-beta.repo"
	BRAVE_REPO_ID="brave-browser-beta"
	BRAVE_PKG="brave-browser-beta"
	BRAVE_KEY_URL="https://brave-browser-rpm-nightly.s3.brave.com/brave-core-nightly.asc"
	BRAVE_KEY_PATH="/etc/pki/rpm-gpg/brave-core-nightly.asc"
	;;
nightly)
	BRAVE_REPO_URL="https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo"
	BRAVE_REPO_PATH="/etc/yum.repos.d/brave-browser-nightly.repo"
	BRAVE_REPO_ID="brave-browser-nightly"
	BRAVE_PKG="brave-browser-nightly"
	BRAVE_KEY_URL="https://brave-browser-rpm-nightly.s3.brave.com/brave-core-nightly.asc"
	BRAVE_KEY_PATH="/etc/pki/rpm-gpg/brave-core-nightly.asc"
	;;
*)
	echo "Unknown BRAVE_CHANNEL='${BRAVE_CHANNEL}' (use: release|beta|nightly)" >&2
	exit 1
	;;
esac

# Ensure curl exists
dnf5 install -y curl

# Add Brave signing key
curl -fsSLo "${BRAVE_KEY_PATH}" "${BRAVE_KEY_URL}"
rpm --import "${BRAVE_KEY_PATH}"

# Add the official Brave RPM repo (Brave’s Atomic instructions fetch the repo file directly)
curl -fsSLo "${BRAVE_REPO_PATH}" "${BRAVE_REPO_URL}"

# Install Brave (Fedora 41+ docs: add repo then dnf install brave-browser)
dnf5 install -y --enablerepo="${BRAVE_REPO_ID}" "${BRAVE_PKG}"

# Move payload to /usr/lib and create stable launcher in /usr/lib
BRAVE_BIN_REL=""
BRAVE_PAYLOAD_DIR="/usr/lib/brave.com"
if [[ -x /opt/brave.com/brave/brave ]]; then
	BRAVE_BIN_REL="brave/brave"
elif [[ -x /opt/brave.com/brave-beta/brave ]]; then
	BRAVE_BIN_REL="brave-beta/brave"
elif [[ -x /opt/brave.com/brave-nightly/brave ]]; then
	BRAVE_BIN_REL="brave-nightly/brave"
fi

if [[ -d /opt/brave.com ]]; then
	install -d /usr/lib
	rm -rf "${BRAVE_PAYLOAD_DIR}"
	mv /opt/brave.com "${BRAVE_PAYLOAD_DIR}"
fi

if [[ -n "${BRAVE_BIN_REL}" ]]; then
	install -d /usr/lib/brave
	cat <<'EOF' >/usr/lib/brave/brave
#!/usr/bin/env bash
exec /usr/lib/brave.com/__BRAVE_BIN_REL__ "$@"
EOF
	sed -i "s|__BRAVE_BIN_REL__|${BRAVE_BIN_REL}|g" /usr/lib/brave/brave
	chmod 0755 /usr/lib/brave/brave
	for bin in /usr/bin/brave-browser /usr/bin/brave-browser-beta /usr/bin/brave-browser-nightly; do
		if [[ -e "${bin}" ]]; then
			ln -sf /usr/lib/brave/brave "${bin}"
		fi
	done
	for desktop in /usr/share/applications/brave*.desktop; do
		if [[ -f "${desktop}" ]]; then
			sed -i 's|^Exec=.*|Exec=/usr/lib/brave/brave|g' "${desktop}"
		fi
	done
fi

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
