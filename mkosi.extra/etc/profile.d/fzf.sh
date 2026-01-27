[[ -n "${BASH_VERSION:-}" ]] || return 0

eval "$(/usr/bin/fzf --bash)"
