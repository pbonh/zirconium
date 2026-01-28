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
  atuin \
  carapace \
  distrobox \
  fd-find \
  fzf \
  kitty \
  libreoffice \
  neovim \
  nu \
  octave \
  ripgrep \
  starship \
  syncthing \
  thunderbird \
  zoxide \
  zsh

# Example using COPR with isolated pattern:
# copr_install_isolated "ublue-os/staging" package-name
copr_install_isolated "jdxcode/mise" mise

# Install ble.sh from source (latest master)
BLESH_DIR="/var/tmp/blesh"
git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git "${BLESH_DIR}"
make -C "${BLESH_DIR}" install DESTDIR=/ PREFIX=/usr
rm -rf "${BLESH_DIR}"

echo "::endgroup::"

echo "::group:: System Configuration"

# Enable/disable systemd services
systemctl enable podman.socket
# Example: systemctl mask unwanted-service

# Install mise bash activation
install -Dpm0755 /ctx/files/etc/profile.d/mise.sh /etc/profile.d/mise.sh
install -Dpm0755 /ctx/files/etc/profile.d/carapace.sh /etc/profile.d/carapace.sh
install -Dpm0755 /ctx/files/etc/profile.d/fzf.sh /etc/profile.d/fzf.sh
install -Dpm0755 /ctx/files/etc/profile.d/starship.sh /etc/profile.d/starship.sh
install -Dpm0755 /ctx/files/etc/profile.d/zoxide.sh /etc/profile.d/zoxide.sh
install -Dpm0755 /ctx/files/etc/profile.d/blesh.sh /etc/profile.d/blesh.sh

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
