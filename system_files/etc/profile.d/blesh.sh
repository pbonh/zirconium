[[ -n "${BASH_VERSION:-}" ]] || return 0

[[ $- == *i* ]] && source -- /usr/share/blesh/ble.sh --attach=none
if [[ ${BLE_VERSION-} ]]; then
  _ble_contrib_fzf_base=/usr/share/fzf
  ble-import -d integration/fzf-completion
  ble-import -d integration/fzf-key-bindings
fi
[[ ! ${BLE_VERSION-} ]] || ble-attach
