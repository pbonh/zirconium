#!/bin/bash
set -ouex pipefail

# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

# Ensure Terra repo is available (installed once in 03-extras)
ensure_terra_repo

# Install Ghostty
# dnf5 install -y --enablerepo=terra --enablerepo=terra-extras ghostty

echo "::group:: Install Ghostty from COPR"
copr_install_isolated "scottames/ghostty" ghostty
echo "::endgroup::"

# Cleanup
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/dnf5 || true
