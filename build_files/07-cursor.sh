#!/bin/bash
set -ouex pipefail

# --- Cursor via upstream AppImage (x86_64/aarch64) ---
# x86_64: https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/2.3
# aarch64: https://api2.cursor.sh/updates/download/golden/linux-arm64/cursor/2.3

# Ensure required tools
# fuse/fuse3 enable AppImage mounting/extraction when needed.
dnf5 install -y curl coreutils fuse fuse3

# Detect architecture and select URL
arch="$(uname -m)"
case "${arch}" in
x86_64 | amd64)
	CURSOR_APPIMAGE_URL="https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/2.3"
	;;
aarch64 | arm64)
	CURSOR_APPIMAGE_URL="https://api2.cursor.sh/updates/download/golden/linux-arm64/cursor/2.3"
	;;
*)
	echo "Unsupported architecture '${arch}'. Supported: x86_64, aarch64" >&2
	exit 1
	;;
esac

TMPDIR="$(mktemp -d)"
APPIMAGE_TEMP="${TMPDIR}/Cursor.AppImage"
APPDIR="/opt/cursor"
APPIMAGE_PATH="${APPDIR}/Cursor.AppImage"
BIN_LINK="/usr/local/bin/cursor"

# Download AppImage
curl -fsSL "${CURSOR_APPIMAGE_URL}" -o "${APPIMAGE_TEMP}"
chmod +x "${APPIMAGE_TEMP}"

# Install AppImage to /opt
install -d "${APPDIR}"
mv "${APPIMAGE_TEMP}" "${APPIMAGE_PATH}"

# Extract resources for desktop integration
pushd "${TMPDIR}"
"${APPIMAGE_PATH}" --appimage-extract
popd

# Install .desktop file, adjusting Exec to point to the symlink
desktop_file="$(find "${TMPDIR}/squashfs-root" -name '*.desktop' | head -n1)"
if [[ -n "${desktop_file}" ]]; then
	sed -i 's|^Exec=.*|Exec=/usr/local/bin/cursor|g' "${desktop_file}"
	install -Dm644 "${desktop_file}" /usr/share/applications/cursor.desktop
fi

# Install icons following XDG hicolor theme paths
find "${TMPDIR}/squashfs-root" -path '*/icons/hicolor/*' -type f -print0 | while IFS= read -r -d '' icon; do
	rel_path="${icon#${TMPDIR}/squashfs-root/}"
	install -Dm644 "${icon}" "/usr/share/${rel_path}"
done

# Fallback: use .DirIcon if present
if [[ -f "${TMPDIR}/squashfs-root/.DirIcon" ]]; then
	install -Dm644 "${TMPDIR}/squashfs-root/.DirIcon" /usr/share/icons/hicolor/512x512/apps/cursor.png
fi

# Symlink into PATH
install -d "$(dirname "${BIN_LINK}")"
ln -sf "${APPIMAGE_PATH}" "${BIN_LINK}"

# Cleanup
rm -rf "${TMPDIR}"
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
