[[ -n "${BASH_VERSION:-}" ]] || return 0

[[ $- == *i* ]] && source -- /usr/share/blesh/ble.sh --attach=none
[[ ! ${BLE_VERSION-} ]] || ble-attach
