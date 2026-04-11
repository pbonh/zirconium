[[ -n "${BASH_VERSION:-}" && $- == *i* ]] || return 0

eval "$(/usr/bin/atuin init bash)"
