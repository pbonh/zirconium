[[ -n "${BASH_VERSION:-}" ]] || return 0

if [[ ! ${__BLESH_SYSTEM_RC_LOADED-} ]]; then
  __BLESH_SYSTEM_RC_LOADED=1

  _ble_rcfile=/etc/blerc

  if [[ -r /usr/share/blesh/ble.sh ]]; then
    source -- /usr/share/blesh/ble.sh --attach=none --rcfile "$_ble_rcfile"
  elif [[ -r /usr/share/blesh/ble.sh.bash ]]; then
    source -- /usr/share/blesh/ble.sh.bash --attach=none --rcfile "$_ble_rcfile"
  fi

  _ble_contrib_fzf_base=/usr/share/fzf
fi
