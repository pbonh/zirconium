#!/usr/bin/bash
set -euo pipefail

###############################################################################
# COPR Helper Functions
###############################################################################
# These helper functions follow the @ublue-os/bluefin pattern for managing
# COPR repositories in a safe, isolated manner.
###############################################################################

copr_install_isolated() {
	local copr_name="$1"
	shift
	local packages=("$@")

	if [[ ${#packages[@]} -eq 0 ]]; then
		echo "ERROR: No packages specified for copr_install_isolated"
		return 1
	fi

	repo_id="copr:copr.fedorainfracloud.org:${copr_name//\//:}"

	echo "Installing ${packages[*]} from COPR $copr_name (isolated)"

	dnf5 -y copr enable "$copr_name"
	dnf5 -y copr disable "$copr_name"
	dnf5 -y install --enablerepo="$repo_id" "${packages[@]}"

	echo "Installed ${packages[*]} from $copr_name"
}

resolve_releasever() {
	if [[ -n "${releasever:-}" ]]; then
		export releasever
		return
	fi

	local detected
	detected="$(rpm -E %fedora 2>/dev/null || true)"
	if [[ -z "${detected}" ]]; then
		detected="$(rpm -E %rhel 2>/dev/null || true)"
	fi
	if [[ -z "${detected}" && -r /etc/os-release ]]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		detected="${VERSION_ID:-}"
	fi

	if [[ -z "${detected}" ]]; then
		echo "releasever is unset and could not be determined" >&2
		return 1
	fi

	releasever="${detected}"
	export releasever
}

ensure_terra_repo() {
	resolve_releasever

	if rpm -q terra-release >/dev/null 2>&1; then
		return
	fi

	dnf5 install -y \
		--nogpgcheck \
		--repofrompath="terra,https://repos.fyralabs.com/terra${releasever}" \
		terra-release
}
