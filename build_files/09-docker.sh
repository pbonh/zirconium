#!/usr/bin/env bash

set -xeuo pipefail

# Docker Engine install via official Fedora repository
# https://docs.docker.com/engine/install/fedora/#install-using-the-repository

DNF_BIN="dnf"
if command -v dnf5 >/dev/null 2>&1; then
  DNF_BIN="dnf5"
fi

${DNF_BIN} -y remove \
  docker \
  docker-client \
  docker-client-latest \
  docker-common \
  docker-latest \
  docker-latest-logrotate \
  docker-logrotate \
  docker-selinux \
  docker-engine-selinux \
  docker-engine || true

${DNF_BIN} -y install 'dnf5-command(config-manager)'
${DNF_BIN} config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo

${DNF_BIN} -y install \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker.service
