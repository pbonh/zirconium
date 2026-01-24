#!/usr/bin/bash

set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Resolve releasever for repo path
resolve_releasever

# Add WezTerm nightly COPR repo using releasever
wget "https://copr.fedorainfracloud.org/coprs/wezfurlong/wezterm-nightly/repo/fedora-${releasever}/wezfurlong-wezterm-nightly-fedora-${releasever}.repo" \
	-O /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:wezfurlong:wezterm-nightly.repo

# Install WezTerm
dnf5 install -y wezterm

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
