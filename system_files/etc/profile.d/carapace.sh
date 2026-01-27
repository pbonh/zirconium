[[ -n "${BASH_VERSION:-}" ]] || return 0

export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
source <(/usr/bin/carapace _carapace)
