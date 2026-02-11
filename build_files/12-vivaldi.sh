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

# Move payload to /usr/lib and create stable launcher in /usr/lib
VIVALDI_BIN_REL=""
if [[ -x /opt/vivaldi/vivaldi ]]; then
	VIVALDI_BIN_REL="vivaldi"
elif [[ -x /opt/vivaldi/vivaldi-bin ]]; then
	VIVALDI_BIN_REL="vivaldi-bin"
fi

if [[ -d /opt/vivaldi ]]; then
	install -d /usr/lib
	rm -rf /usr/lib/vivaldi
	mv /opt/vivaldi /usr/lib/
fi

if [[ -n "${VIVALDI_BIN_REL}" ]]; then
	install -d /usr/lib/vivaldi
	cat <<'EOF' >/usr/lib/vivaldi/vivaldi
#!/usr/bin/env bash
exec /usr/lib/vivaldi/__VIVALDI_BIN_REL__ "$@"
EOF
	sed -i "s|__VIVALDI_BIN_REL__|${VIVALDI_BIN_REL}|g" /usr/lib/vivaldi/vivaldi
	chmod 0755 /usr/lib/vivaldi/vivaldi
	if [[ -e /usr/bin/vivaldi-stable ]]; then
		ln -sf /usr/lib/vivaldi/vivaldi /usr/bin/vivaldi-stable
	fi
	for desktop in /usr/share/applications/vivaldi*.desktop; do
		if [[ -f "${desktop}" ]]; then
			sed -i 's|^Exec=.*|Exec=/usr/lib/vivaldi/vivaldi|g' "${desktop}"
		fi
	done
fi

# Cleanup
rm -f "${VIVALDI_RPM_PATH}"
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
