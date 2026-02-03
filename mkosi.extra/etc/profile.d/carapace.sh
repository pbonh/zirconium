[[ -n "${BASH_VERSION:-}" && $- == *i* ]] || return 0

export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
source <(/usr/bin/carapace _carapace)
