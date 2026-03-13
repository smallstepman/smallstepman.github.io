#!/usr/bin/env bash
# tests/den/darwin.sh
#
# Verifies Task 9 of the den migration:
#   - den/aspects/features/darwin-core.nix  (new)
#   - den/aspects/features/homebrew.nix     (new)
#   - den/aspects/features/launchd.nix      (new)
#   - den/aspects/hosts/macbook-pro-m1.nix wires the new aspects
#   - machines/macbook-pro-m1.nix and users/m/darwin.nix no longer own the
#     migrated settings

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# ---------------------------------------------------------------------------
# Static structure checks — new aspect files must exist
# ---------------------------------------------------------------------------

test -f den/aspects/features/darwin-core.nix \
  || { echo "FAIL: den/aspects/features/darwin-core.nix missing" >&2; exit 1; }
test -f den/aspects/features/homebrew.nix \
  || { echo "FAIL: den/aspects/features/homebrew.nix missing" >&2; exit 1; }
test -f den/aspects/features/launchd.nix \
  || { echo "FAIL: den/aspects/features/launchd.nix missing" >&2; exit 1; }

grep -Fq 'system.stateVersion = 5;'           den/aspects/features/darwin-core.nix
grep -Fq 'nix.enable = false;'                den/aspects/features/darwin-core.nix
grep -Fq 'services.openssh.enable = true;'    den/aspects/features/darwin-core.nix
grep -Fq 'openssh.authorizedKeys.keyFiles'    den/aspects/features/darwin-core.nix
grep -Fq 'homebrew.enable = true;'            den/aspects/features/homebrew.nix
grep -Fq 'launchd.user.agents.uniclip'        den/aspects/features/launchd.nix
grep -Fq 'AW_IMPORT_SRC'                      den/aspects/features/launchd.nix

grep -Fq 'den.aspects.darwin-core'            den/aspects/hosts/macbook-pro-m1.nix
grep -Fq 'den.aspects.homebrew'               den/aspects/hosts/macbook-pro-m1.nix
grep -Fq 'den.aspects.launchd'                den/aspects/hosts/macbook-pro-m1.nix

# ---------------------------------------------------------------------------
# Guard: migrated system-level items must no longer remain in
# machines/macbook-pro-m1.nix
# ---------------------------------------------------------------------------

darwin_machine=machines/macbook-pro-m1.nix
for item in \
  'system.stateVersion = 5;' \
  'nix.enable = false;' \
  'services.openssh' \
  'security.pam.services.sudo_local'; do
  non_comment=$(grep -Ev '^[[:space:]]*#' "$darwin_machine" || true)
  if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
    echo "FAIL: $darwin_machine still contains '$item' (should be in darwin-core.nix)" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Guard: migrated Darwin user/system items must no longer remain in
# users/m/darwin.nix
# ---------------------------------------------------------------------------

darwin_user=users/m/darwin.nix
for item in \
  'homebrew = {' \
  'system.primaryUser = "m";' \
  'launchd.user.agents.uniclip' \
  'launchd.user.agents.openwebui' \
  'launchd.user.agents.activitywatch-sync-ios-screentime-to-aw'; do
  non_comment=$(grep -Ev '^[[:space:]]*#' "$darwin_user" || true)
  if printf '%s\n' "$non_comment" | grep -Fq "$item"; then
    echo "FAIL: $darwin_user still contains '$item' (should be in a den aspect)" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Live nix eval helper
# ---------------------------------------------------------------------------

_nix_eval() {
  local fmt="$1" attr="$2" out err_file
  err_file=$(mktemp)
  if ! out=$(nix eval --impure "$fmt" "$attr" 2>"$err_file"); then
    echo "FAIL: nix eval '$attr' failed with:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 1
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  printf '%s' "$out"
}

nix_eval_raw()  { _nix_eval --raw  "$1"; }
nix_eval_json() { _nix_eval --json "$1"; }

nix_eval_expr_raw() {
  local expr="$1" out err_file
  err_file=$(mktemp)
  if ! out=$(nix eval --impure --raw --expr "$expr" 2>"$err_file"); then
    echo "FAIL: nix eval expr failed with:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    exit 1
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Live eval: Darwin system settings
# ---------------------------------------------------------------------------

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.nix.enable")
[ "$actual" = "false" ] \
  || { echo "FAIL: nix.enable: expected false, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.services.openssh.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: services.openssh.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.services.openssh.extraConfig")
printf '%s' "$actual" | grep -Fq 'ListenAddress 192.168.130.1' \
  || { echo "FAIL: services.openssh.extraConfig missing ListenAddress 192.168.130.1" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.homebrew.enable")
[ "$actual" = "true" ] \
  || { echo "FAIL: homebrew.enable: expected true, got $actual" >&2; exit 1; }

actual=$(nix_eval_raw ".#darwinConfigurations.macbook-pro-m1.config.system.primaryUser")
[ "$actual" = "m" ] \
  || { echo "FAIL: system.primaryUser: expected m, got $actual" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.system.stateVersion")
[ "$actual" = "5" ] \
  || { echo "FAIL: system.stateVersion: expected 5, got $actual" >&2; exit 1; }

actual=$(nix_eval_expr_raw 'let flake = builtins.getFlake (toString ./.); in if flake.darwinConfigurations.macbook-pro-m1.pkgs ? uniclip then "yes" else "no"')
[ "$actual" = "yes" ] \
  || { echo "FAIL: darwin system pkgs missing overlay package uniclip" >&2; exit 1; }

actual=$(nix_eval_expr_raw 'let flake = builtins.getFlake (toString ./.); in if flake.nixosConfigurations.vm-aarch64.pkgs ? uniclip then "yes" else "no"')
[ "$actual" = "yes" ] \
  || { echo "FAIL: vm system pkgs missing overlay package uniclip" >&2; exit 1; }

actual=$(nix_eval_json ".#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents.uniclip.serviceConfig.RunAtLoad")
[ "$actual" = "true" ] \
  || { echo "FAIL: launchd.user.agents.uniclip.serviceConfig.RunAtLoad: expected true, got $actual" >&2; exit 1; }

echo "All darwin checks passed."
