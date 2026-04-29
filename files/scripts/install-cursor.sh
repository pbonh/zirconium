#!/usr/bin/env bash
set -euo pipefail

# Installs Cursor from the official AppImage.
# Extracts the .desktop file and icons so Cursor shows up in the launcher,
# installs the AppImage under /opt/cursor/, and creates a /usr/bin/cursor
# wrapper that exec's the AppImage.

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  CURSOR_ARCH=x64   ;;
    aarch64) CURSOR_ARCH=arm64 ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# Cursor's official "stable, latest" download endpoint.
# If this URL changes upstream, the build fails — that's intentional;
# we want a loud failure rather than silently producing an image without Cursor.
DOWNLOAD_URL="https://api2.cursor.sh/updates/api/download/stable/linux-${CURSOR_ARCH}/cursor"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "==> Downloading Cursor AppImage from $DOWNLOAD_URL"
curl -fL --retry 3 --retry-delay 5 -o cursor.AppImage "$DOWNLOAD_URL"
chmod +x cursor.AppImage

echo "==> Extracting AppImage contents"
./cursor.AppImage --appimage-extract >/dev/null
test -d squashfs-root || { echo "AppImage extraction produced no squashfs-root" >&2; exit 1; }

echo "==> Installing AppImage to /opt/cursor/"
mkdir -p /opt/cursor
cp cursor.AppImage /opt/cursor/cursor.AppImage
chmod 0755 /opt/cursor/cursor.AppImage

echo "==> Installing .desktop file"
DESKTOP_SRC="$(find squashfs-root -maxdepth 3 -name '*.desktop' | head -n1)"
test -n "$DESKTOP_SRC" || { echo "No .desktop file found in AppImage" >&2; exit 1; }
mkdir -p /usr/share/applications
sed -e 's|^Exec=.*|Exec=/usr/bin/cursor %F|' \
    -e 's|^Icon=.*|Icon=cursor|' \
    -e 's|^TryExec=.*|TryExec=/usr/bin/cursor|' \
    "$DESKTOP_SRC" > /usr/share/applications/cursor.desktop
chmod 0644 /usr/share/applications/cursor.desktop

echo "==> Installing icons"
ICONS_INSTALLED=0
for size in 16 24 32 48 64 96 128 256 512; do
    SRC=$(find squashfs-root -path "*${size}x${size}*" -name '*.png' 2>/dev/null | head -n1)
    if [ -n "$SRC" ] && [ -f "$SRC" ]; then
        DEST=/usr/share/icons/hicolor/${size}x${size}/apps
        mkdir -p "$DEST"
        cp "$SRC" "$DEST/cursor.png"
        ICONS_INSTALLED=$((ICONS_INSTALLED + 1))
    fi
done
if [ "$ICONS_INSTALLED" -eq 0 ]; then
    # Fallback: any PNG icon at the AppImage root
    FALLBACK=$(find squashfs-root -maxdepth 2 -name '*.png' | head -n1)
    if [ -n "$FALLBACK" ]; then
        DEST=/usr/share/icons/hicolor/256x256/apps
        mkdir -p "$DEST"
        cp "$FALLBACK" "$DEST/cursor.png"
        ICONS_INSTALLED=1
    fi
fi
[ "$ICONS_INSTALLED" -gt 0 ] || { echo "No icons found in AppImage" >&2; exit 1; }
echo "    installed $ICONS_INSTALLED icon size(s)"

echo "==> Creating /usr/bin/cursor wrapper"
cat > /usr/bin/cursor <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/cursor/cursor.AppImage --no-sandbox "$@"
WRAPPER
chmod 0755 /usr/bin/cursor

echo "==> Cursor installation complete"
