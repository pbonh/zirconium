#!/usr/bin/env bash

set -xeuo pipefail

# Docker Engine install via official Fedora repository
# https://docs.docker.com/engine/install/fedora/#install-using-the-repository

DNF_BIN="dnf"
if command -v dnf5 >/dev/null 2>&1; then
	DNF_BIN="dnf5"
fi

arch="${TARGETARCH:-$(uname -m)}"
case "${arch}" in
x86_64 | amd64)
	docker_basearch="x86_64"
	;;
aarch64 | arm64)
	docker_basearch="aarch64"
	;;
*)
	echo "Unsupported architecture '${arch}'. Supported: x86_64, aarch64" >&2
	exit 1
	;;
esac

# Docker does not currently publish full engine packages for Fedora 44.
# Pin to Fedora 43 Docker repo for both x86_64 and aarch64 until 44 is complete.
DOCKER_FEDORA_RELEASE="${DOCKER_FEDORA_RELEASE:-43}"
DOCKER_REPO_URL="https://download.docker.com/linux/fedora/${DOCKER_FEDORA_RELEASE}/${docker_basearch}/stable"
DOCKER_REPO_FILE="/etc/yum.repos.d/docker-ce.repo"

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

cat >"${DOCKER_REPO_FILE}" <<EOF
[docker-ce-stable]
name=Docker CE Stable - Fedora ${DOCKER_FEDORA_RELEASE} (${docker_basearch})
baseurl=${DOCKER_REPO_URL}
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/fedora/gpg
EOF

${DNF_BIN} -y install \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin

systemctl enable docker.service
systemctl enable containerd.service
