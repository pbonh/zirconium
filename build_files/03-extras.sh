#!/usr/bin/bash

set -eoux pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -eoux pipefail for strict error handling and debugging.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Ensure Terra repo is available once for all downstream installs
ensure_terra_repo

echo "::group:: Install Extra System Packages"

dnf5 install -y alacritty \
	ansible \
	distrobox \
	fd-find \
	fzf \
	kitty \
	libreoffice \
	neovim \
	nu \
	octave \
	ripgrep \
	syncthing \
	thunderbird \
	zsh

# Example using COPR with isolated pattern:
# copr_install_isolated "ublue-os/staging" package-name

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

# Install and globally enable tailscale systray (user service)
install -d /usr/lib/systemd/user /etc/systemd/user/default.target.wants
cat <<'EOF' >/usr/lib/systemd/user/tailscale-systray.service
[Unit]
Description=Tailscale System Tray
After=systemd.service

[Service]
Type=simple
ExecStart=/usr/bin/tailscale systray

[Install]
WantedBy=default.target
EOF
ln -sf /usr/lib/systemd/user/tailscale-systray.service /etc/systemd/user/default.target.wants/tailscale-systray.service

echo "::endgroup::"

echo "Custom build complete!"
