#!/usr/bin/env bash

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

  printf '%s' "$dir"
}

generated_input_flake_ref() {
  printf 'path:%s' "$(generated_input_dir)"
}

yeet_and_yoink_input_dir() {
  local dir="${YEET_AND_YOINK_INPUT_DIR:-}"
  if [ -z "$dir" ]; then
    if [ -d "$HOME/Projects/yeet-and-yoink" ]; then
      dir="$HOME/Projects/yeet-and-yoink"
    elif [ -d /Users/m/Projects/yeet-and-yoink ]; then
      dir=/Users/m/Projects/yeet-and-yoink
    else
      printf 'FAIL: yeet-and-yoink source missing; set YEET_AND_YOINK_INPUT_DIR or expose /Users/m/Projects/yeet-and-yoink\n' >&2
      return 1
    fi
  fi

  if [ ! -d "$dir" ]; then
    printf 'FAIL: yeet-and-yoink directory does not exist: %s\n' "$dir" >&2
    return 1
  fi

  printf '%s' "$dir"
}

yeet_and_yoink_input_flake_ref() {
  printf 'git+file://%s?dir=plugins/zellij-break' "$(yeet_and_yoink_input_dir)"
}

nix_generated_eval() {
  nix --extra-experimental-features 'nix-command flakes' eval \
    --no-write-lock-file \
    --override-input generated "$(generated_input_flake_ref)" \
    --override-input yeetAndYoink "$(yeet_and_yoink_input_flake_ref)" \
    "$@"
}

nix_generated_build() {
  nix --extra-experimental-features 'nix-command flakes' build \
    --no-write-lock-file \
    --override-input generated "$(generated_input_flake_ref)" \
    --override-input yeetAndYoink "$(yeet_and_yoink_input_flake_ref)" \
    "$@"
}

nix_generated_run() {
  nix --extra-experimental-features 'nix-command flakes' run \
    --no-write-lock-file \
    --override-input generated "$(generated_input_flake_ref)" \
    --override-input yeetAndYoink "$(yeet_and_yoink_input_flake_ref)" \
    "$@"
}
