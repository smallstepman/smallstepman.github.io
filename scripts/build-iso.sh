#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export NIX_CONFIG_DIR="$PWD"
if [ -f .env ]; then
  set -a; source .env; set +a
fi
: "${WIFI_SSID:?Set WIFI_SSID in .env}"

if [ -z "${WIFI_PSK:-}" ]; then
  if [ -n "${WIFI_PSK_RBW_ITEM:-}" ]; then
    command -v rbw >/dev/null || {
      echo "WIFI_PSK_RBW_ITEM is set, but rbw is unavailable" >&2
      exit 1
    }
    WIFI_PSK="$(rbw get "$WIFI_PSK_RBW_ITEM")"
  elif [ -n "${WIFI_PSK_FILE:-}" ]; then
    WIFI_PSK="$(< "$WIFI_PSK_FILE")"
  else
    echo "Set WIFI_PSK_RBW_ITEM, WIFI_PSK_FILE, or WIFI_PSK" >&2
    exit 1
  fi
fi

: "${WIFI_PSK:?The resolved Wi-Fi PSK is empty}"
export WIFI_SSID WIFI_PSK
exec nix build --impure -f scripts/jimi-installer.nix "$@"
