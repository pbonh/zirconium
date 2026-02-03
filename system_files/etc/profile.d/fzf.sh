[[ -n "${BASH_VERSION:-}" && $- == *i* ]] || return 0

if [[ ! ${BLE_VERSION-} ]]; then
	eval "$(/usr/bin/fzf --bash)"
fi
