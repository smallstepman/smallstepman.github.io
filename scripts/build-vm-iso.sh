#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export NIX_CONFIG_DIR="$PWD"

export VM_AGE_KEY VM_AGE_KEY_FILE
exec nix build --impure -f scripts/vm-installer.nix "$@"
