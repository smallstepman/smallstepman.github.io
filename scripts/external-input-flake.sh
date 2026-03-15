#!/usr/bin/env bash

_external_input_flake_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)

canonicalize_dir() {
  (cd "$1" >/dev/null 2>&1 && pwd -P)
}

external_input_repo_root() {
  local repo_root="${NIX_CONFIG_DIR:-}"
  if [ -n "$repo_root" ]; then
    canonicalize_dir "$repo_root"
  else
    (cd "${_external_input_flake_script_dir}/.." >/dev/null 2>&1 && pwd)
  fi
}

generated_input_dir() {
  local dir="${GENERATED_INPUT_DIR:-}"
  if [ -z "$dir" ]; then
    if [ -d "$HOME/.local/share/nix-config-generated" ]; then
      dir="$HOME/.local/share/nix-config-generated"
    elif [ -d /nixos-generated ]; then
      dir=/nixos-generated
    else
      printf 'FAIL: generated dataset missing; set GENERATED_INPUT_DIR or create ~/.local/share/nix-config-generated (host) or /nixos-generated (VM)\n' >&2
      return 1
    fi
  fi

  if [ ! -d "$dir" ]; then
    printf 'FAIL: generated dataset directory does not exist: %s\n' "$dir" >&2
    return 1
  fi

  canonicalize_dir "$dir"
}

mk_wrapper_flake() {
  if [ -n "${_nix_wrapper_dir:-}" ] && [ -f "${_nix_wrapper_dir}/flake.nix" ]; then
    printf '%s\n' "$_nix_wrapper_dir"
    return 0
  fi

  local generated_dir repo_root tmp_root wrapper_dir
  generated_dir=$(generated_input_dir) || return 1
  repo_root=$(external_input_repo_root) || return 1
  tmp_root="${TMPDIR:-/tmp}"
  wrapper_dir=$(mktemp -d "${tmp_root%/}/nix-wrapper-XXXXXX") || return 1
  wrapper_dir=$(cd "$wrapper_dir" >/dev/null 2>&1 && pwd -P) || return 1

  cat >"$wrapper_dir/flake.nix" <<EOF
{
  inputs.config.url = "path:$repo_root";
  inputs.generated = { url = "path:$generated_dir"; flake = false; };
  outputs = { config, generated, ... }@inputs: config.lib.mkOutputs { inherit generated; };
}
EOF

  local lock_stderr="$wrapper_dir/.flake-lock.stderr"
  if ! (cd "$wrapper_dir" >/dev/null 2>&1 && nix flake lock >/dev/null 2>"$lock_stderr"); then
    cat "$lock_stderr" >&2
    rm -f "$lock_stderr"
    return 1
  fi
  rm -f "$lock_stderr"

  _nix_wrapper_dir="$wrapper_dir"
  printf '%s\n' "$wrapper_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  _nix_wrapper_dir=""
  mk_wrapper_flake
fi
