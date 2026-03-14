#!/usr/bin/env bats
# tests.bats — Unified Bats test suite for the Nix configuration repository.
#
# Migrated from the per-script tests/ directory.  All legacy shell entrypoints
# under tests/ have been removed; this is the single source of truth.
#
# Usage:
#   bats tests.bats                           # run everything
#   bats --filter-tags no-legacy tests.bats   # run a tagged subset
#   bats --jobs 4 tests.bats                  # run in parallel (requires GNU parallel)

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

# ---------------------------------------------------------------------------
# Global initialisation (runs once per test subshell on file load)
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"

# Source the wrapper-flake helpers (defines mk_wrapper_flake and friends).
# The script guards its own main body so sourcing is always safe.
# shellcheck source=scripts/external-input-flake.sh
. "$REPO_ROOT/scripts/external-input-flake.sh"

# Wrapper around `nix eval / build / run` that injects the generated and
# yeet-and-yoink inputs via a temporary wrapper flake.
_nix_with_wrapper() {
  local cmd="$1"; shift
  local wrapper_dir
  wrapper_dir=$(mk_wrapper_flake) || return 1
  local args=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      .#*) args+=("path:$wrapper_dir#${arg#.#}") ;;
      *) args+=("$arg") ;;
    esac
  done
  nix --extra-experimental-features 'nix-command flakes' "$cmd" \
    --no-write-lock-file \
    "${args[@]}"
}

nix_generated_eval()  { _nix_with_wrapper eval  "$@"; }
nix_generated_build() { _nix_with_wrapper build "$@"; }
nix_generated_run()   { _nix_with_wrapper run   "$@"; }

# Capture stdout; forward stderr; fail with context on non-zero exit.
_nix_eval() {
  local fmt="$1" attr="$2" out err_file
  err_file=$(mktemp)
  if ! out=$(nix_generated_eval "$fmt" "$attr" 2>"$err_file"); then
    echo "nix_generated_eval '$attr' failed:" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  printf '%s' "$out"
}
nix_eval_raw()  { _nix_eval --raw  "$1"; }
nix_eval_json() { _nix_eval --json "$1"; }

nix_eval_apply_raw() {
  local attr="$1" apply="$2" out err_file
  err_file=$(mktemp)
  if ! out=$(nix_generated_eval --raw --apply "$apply" "$attr" 2>"$err_file"); then
    echo "nix_generated_eval apply failed for '$attr':" >&2
    cat "$err_file" >&2
    rm -f "$err_file"
    return 1
  fi
  cat "$err_file" >&2
  rm -f "$err_file"
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Per-test setup: ensure we're always at the repo root
# ---------------------------------------------------------------------------

setup() {
  cd "$REPO_ROOT"
}

# Pre-create the wrapper flake once per suite run so each test subshell
# can reuse it (mk_wrapper_flake short-circuits when the dir already exists).
setup_file() {
  cd "$REPO_ROOT"
  export _nix_wrapper_dir=""
  _nix_wrapper_dir=$(mk_wrapper_flake)
}


# ===========================================================================
# no-legacy — legacy composition files are removed; structure is modernised
# ===========================================================================

# bats test_tags=no-legacy
@test "no-legacy: legacy files and directories are absent" {
  for legacy_path in \
    den/legacy.nix \
    lib/mksystem.nix \
    machines \
    machines/vm-aarch64.nix \
    machines/vm-shared.nix \
    machines/macbook-pro-m1.nix \
    machines/wsl.nix \
    users/m \
    users/m/home-manager.nix \
    users/m/nixos.nix \
    users/m/darwin.nix; do
    assert [ ! -e "$legacy_path" ] || fail "legacy path still exists: $legacy_path"
  done
}

# bats test_tags=no-legacy
@test "no-legacy: required dotfile directories exist" {
  for required_dir in \
    dotfiles/common \
    dotfiles/by-host/darwin \
    dotfiles/by-host/vm \
    dotfiles/by-host/wsl; do
    assert_dir_exists "$required_dir"
  done
}

# bats test_tags=no-legacy
@test "no-legacy: generated/ artifacts are not tracked in git" {
  local tracked_generated
  tracked_generated=$(git ls-files 'generated/*')
  assert [ -z "$tracked_generated" ] || fail "generated/ artifacts still tracked: $tracked_generated"
}

# bats test_tags=no-legacy
@test "no-legacy: flake.nix exports lib.mkOutputs" {
  grep -Fq 'lib.mkOutputs' flake.nix
}

# bats test_tags=no-legacy
@test "no-legacy: secrets.yaml sourced from generated input" {
  grep -Fq 'generated.requireFile "secrets.yaml"' den/aspects/features/secrets.nix
}

# bats test_tags=no-legacy
@test "no-legacy: darwin-core sources mac-host-authorized-keys from generated input" {
  grep -Fq '(generated.requireFile "mac-host-authorized-keys")' den/aspects/features/darwin-core.nix
}

# bats test_tags=no-legacy
@test "no-legacy: vm-aarch64 sources vm-age-pubkey and host-authorized-keys from generated input" {
  grep -Fq 'generated.readFile "vm-age-pubkey"' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '(generated.requireFile "host-authorized-keys")' den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=no-legacy
@test "no-legacy: .gitignore ignores local generated/ copies" {
  grep -Fxq 'generated/' .gitignore
}

# bats test_tags=no-legacy
@test "no-legacy: den/default.nix imports inputs.den.flakeModule" {
  grep -Fq 'inputs.den.flakeModule' den/default.nix
}

# bats test_tags=no-legacy
@test "no-legacy: den/mk-config-outputs.nix builds system outputs" {
  grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' den/mk-config-outputs.nix
}

# bats test_tags=no-legacy
@test "no-legacy: den/default.nix owns global nixpkgs overlays and allowUnfree" {
  grep -Fq 'nixpkgs.overlays = overlays;' den/default.nix
  grep -Fq 'nixpkgs.config.allowUnfree = true;' den/default.nix
}

# bats test_tags=no-legacy
@test "no-legacy: den/default.nix does not centralise Linux-only flake-module imports" {
  if rg -n \
    'inputs\.(sops-nix|sopsidy|nix-snapd|niri|disko|mangowc|noctalia|nixos-wsl)\.nixosModules' \
    den/default.nix >/dev/null; then
    fail 'den/default.nix still centralizes Linux-only flake-module imports'
  fi
}

# bats test_tags=no-legacy
@test "no-legacy: aspect files own their respective flake module imports" {
  grep -Fq 'inputs.sops-nix.nixosModules.sops' den/aspects/features/secrets.nix
  grep -Fq 'inputs.sopsidy.nixosModules.default' den/aspects/features/secrets.nix
  grep -Fq 'inputs.nix-snapd.nixosModules.default' den/aspects/features/linux-core.nix
  grep -Fq 'inputs.niri.nixosModules.niri' den/aspects/features/linux-desktop.nix
  grep -Fq 'inputs.mangowc.nixosModules.mango' den/aspects/features/linux-desktop.nix
  grep -Fq 'inputs.noctalia.nixosModules.default' den/aspects/features/linux-desktop.nix
  if rg -n 'inputs\.nixos-wsl\.nixosModules\.wsl' den/aspects/features >/dev/null; then
    fail 'WSL flake-module import should be owned upstream, not by den/aspects/features/*'
  fi
  grep -Fq 'inputs.disko.nixosModules.disko' den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=no-legacy
@test "no-legacy: repository does not reference den/legacy.nix" {
  if grep -R -Fq --exclude 'tests.bats' 'den/legacy.nix' \
    flake.nix \
    den \
    README.md \
    AGENTS.md \
    docs/secrets.md \
    docs/clipboard-sharing.md; then
    fail 'repository still references den/legacy.nix after cleanup'
  fi
}

# bats test_tags=no-legacy
@test "no-legacy: repository does not reference users/m or machines/* runtime paths" {
  if rg -n --glob '!tests.bats' \
    'users/m/|machines/generated|machines/secrets\.yaml|machines/hardware/' \
    den README.md AGENTS.md docs/*.md docs/*.sh flake.nix >/dev/null; then
    fail 'repository still references users/m or machines/* runtime paths after layout cleanup'
  fi
}

# bats test_tags=no-legacy
@test "no-legacy: vm-aarch64 hostname evaluates correctly" {
  local vm_hostname
  vm_hostname=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.networking.hostName)
  assert_equal "$vm_hostname" "vm-macbook"
}

# bats test_tags=no-legacy
@test "no-legacy: vm-aarch64 disko root mountpoint is /" {
  local vm_root_mount
  vm_root_mount=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.disko.devices.disk.main.content.partitions.root.content.mountpoint)
  assert_equal "$vm_root_mount" "/"
}

# bats test_tags=no-legacy
@test "no-legacy: macbook-pro-m1 primary user is m" {
  local darwin_primary_user
  darwin_primary_user=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser)
  assert_equal "$darwin_primary_user" "m"
}

# bats test_tags=no-legacy
@test "no-legacy: wsl.enable evaluates to true" {
  local wsl_enabled
  wsl_enabled=$(nix_eval_json .#nixosConfigurations.wsl.config.wsl.enable)
  assert_equal "$wsl_enabled" "true"
}


# ===========================================================================
# flake-smoke — flake inputs and lock are consistent
# ===========================================================================

# bats test_tags=flake-smoke
@test "flake-smoke: flake.nix references den and flake-aspects" {
  grep -Fq 'inputs.den.url = "github:vic/den";' flake.nix
  grep -Fq 'inputs.den.flakeModule' den/default.nix
  grep -Fq 'flake-aspects.url = "github:vic/flake-aspects"' flake.nix
}

# bats test_tags=flake-smoke
@test "flake-smoke: den/legacy.nix is absent" {
  assert [ ! -e den/legacy.nix ]
}

# bats test_tags=flake-smoke
@test "flake-smoke: mk-config-outputs wires system outputs" {
  grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' den/mk-config-outputs.nix
}

# bats test_tags=flake-smoke
@test "flake-smoke: flake.lock carries a root-level flake-aspects entry" {
  python3 - <<'PYEOF'
import json, sys
with open("flake.lock") as f:
    lock = json.load(f)
root_inputs = lock["nodes"]["root"].get("inputs", {})
if "flake-aspects" not in root_inputs:
    print("flake.lock root is missing required 'flake-aspects' input", file=sys.stderr)
    sys.exit(1)
PYEOF
}


# ===========================================================================
# host-schema — den schema options are declared correctly
# ===========================================================================

# bats test_tags=host-schema
@test "host-schema: hosts.nix declares all three hosts" {
  grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.users.m' den/hosts.nix
  grep -Fq 'den.hosts.aarch64-darwin.macbook-pro-m1.users.m' den/hosts.nix
  grep -Fq 'den.hosts.x86_64-linux.wsl.users.m' den/hosts.nix
}

# bats test_tags=host-schema
@test "host-schema: den/default.nix keeps hm-host wiring and does not add WSL aliases" {
  grep -Fq 'den.ctx.hm-host.includes' den/default.nix
  if grep -Fq 'den._.wsl' den/default.nix; then
    fail 'den/default.nix must not include den._.wsl; WSL is enabled per-host via den.hosts.x86_64-linux.wsl.wsl.enable'
  fi
  if grep -Fq 'den.provides.wsl' den/default.nix; then
    fail 'den/default.nix must not redeclare or include den.provides.wsl'
  fi
}

# bats test_tags=host-schema
@test "host-schema: den/default.nix drops profile schema and keeps remaining host flags" {
  if grep -Fq 'options.profile' den/default.nix; then
    fail 'profile should be removed from den/default.nix'
  fi
  grep -Fq 'options.vmware.enable' den/default.nix
  grep -Fq 'options.graphical.enable' den/default.nix
}

# bats test_tags=host-schema
@test "host-schema: options.wsl.enable is not redeclared in den/default.nix" {
  if grep -Fq 'options.wsl.enable' den/default.nix; then
    fail 'options.wsl.enable must not be declared in den/default.nix (conflicts with den upstream)'
  fi
}

# bats test_tags=host-schema
@test "host-schema: hosts.nix keeps den-provided and migration host flags" {
  grep -Fq 'den.hosts.x86_64-linux.wsl.wsl.enable = true' den/hosts.nix
  grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.vmware.enable = true' den/hosts.nix
  grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.graphical.enable = true' den/hosts.nix
}

# bats test_tags=host-schema
@test "host-schema: hosts.nix removes only profile assignments" {
  if rg -n 'profile = ' den/hosts.nix >/dev/null; then
    fail 'den/hosts.nix should drop only profile host assignments in Task 1'
  fi
}


# ===========================================================================
# identity — identity aspect wires den-native user/host context
# ===========================================================================

# bats test_tags=identity
@test "identity: identity.nix provides key user-context batteries" {
  grep -Fq 'den.provides.define-user' den/aspects/features/identity.nix
  grep -Fq 'den.provides.primary-user' den/aspects/features/identity.nix
  grep -Fq 'den.provides.user-shell' den/aspects/features/identity.nix
}

# bats test_tags=identity
@test "identity: user m aspect references the identity aspect" {
  grep -Fq 'den.aspects.identity' den/aspects/users/m.nix
}

# bats test_tags=identity
@test "identity: vm-aarch64 host aspect includes the hostname battery" {
  grep -Fq 'den.provides.hostname' den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=identity
@test "identity: hosts.nix carries the vm-macbook hostname" {
  grep -Fq 'vm-macbook' den/hosts.nix
}

# bats test_tags=identity
@test "identity: host aspect files exist for macbook-pro-m1 and wsl" {
  assert_file_exists den/aspects/hosts/macbook-pro-m1.nix
  assert_file_exists den/aspects/hosts/wsl.nix
}

# bats test_tags=identity
@test "identity: vm-aarch64 hostName evaluates to vm-macbook" {
  local actual
  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.networking.hostName)
  assert_equal "$actual" "vm-macbook"
}

# bats test_tags=identity
@test "identity: macbook-pro-m1 primaryUser evaluates to m" {
  local actual
  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser)
  assert_equal "$actual" "m"
}

# bats test_tags=identity
@test "identity: wsl defaultUser evaluates to m" {
  local actual
  actual=$(nix_eval_raw .#nixosConfigurations.wsl.config.wsl.defaultUser)
  assert_equal "$actual" "m"
}

# bats test_tags=identity
@test "identity: vm-aarch64 hostName is defined by den hostname.nix (provenance)" {
  local defs
  defs=$(nix_eval_json .#nixosConfigurations.vm-aarch64.options.networking.hostName.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'hostname.nix' \
    || fail "vm-aarch64 hostName not defined by modules/aspects/provides/hostname.nix; got: $defs"
}

# bats test_tags=identity
@test "identity: macbook-pro-m1 primaryUser is defined by den primary-user.nix (provenance)" {
  local defs
  defs=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.options.system.primaryUser.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'primary-user.nix' \
    || fail "macbook-pro-m1 primaryUser not defined by modules/aspects/provides/primary-user.nix; got: $defs"
}

# bats test_tags=identity
@test "identity: wsl defaultUser is defined by den provides/wsl.nix (provenance)" {
  local defs
  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.wsl.defaultUser.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'provides/wsl.nix' \
    || fail "wsl defaultUser not defined by modules/aspects/provides/wsl.nix; got: $defs"
}


# ===========================================================================
# home-manager-core — HM wiring and shell-git / home-base aspects
# ===========================================================================

# bats test_tags=home-manager-core
@test "home-manager-core: shell-git and home-base aspect files exist" {
  assert_file_exists den/aspects/features/shell-git.nix
  assert_file_exists den/aspects/features/home-base.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: den/default.nix uses hm-host (not host) for HM wiring" {
  grep -Fq 'den.ctx.hm-host.includes' den/default.nix
  if grep -Fq 'den.ctx.host.includes' den/default.nix; then
    fail 'den/default.nix still centralizes host wiring under den.ctx.host.includes'
  fi
}

# bats test_tags=home-manager-core
@test "home-manager-core: shell-git.nix sets essential HM programs" {
  grep -Fq 'programs.git = {' den/aspects/features/shell-git.nix
  grep -Fq 'programs.zsh = {' den/aspects/features/shell-git.nix
  grep -Fq 'programs.oh-my-posh = {' den/aspects/features/shell-git.nix
  grep -Fq 'programs.direnv = {' den/aspects/features/shell-git.nix
  grep -Fq 'programs.atuin = {' den/aspects/features/shell-git.nix
  grep -Fq 'programs.zoxide = {' den/aspects/features/shell-git.nix
  grep -Fq 'programs.gh = {' den/aspects/features/shell-git.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: shell-git.nix sets EDITOR session variable" {
  grep -Fq 'EDITOR' den/aspects/features/shell-git.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: home-base.nix owns remaining user-level HM config" {
  grep -Fq 'programs.rbw = lib.mkIf isLinux' den/aspects/features/home-base.nix
  grep -Fq '"grm/repos.yaml"' den/aspects/features/home-base.nix
  grep -Fq 'ghostty-bin' den/aspects/features/home-base.nix
  grep -Fq '"wezterm/wezterm.lua"' den/aspects/features/home-base.nix
  grep -Fq 'den.aspects.home-base' den/aspects/users/m.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: shell-git includes g = git alias" {
  grep -Eq '(^|[[:space:]])g[[:space:]]*=[[:space:]]*"git";' den/aspects/features/shell-git.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: user m aspect includes shell-git" {
  grep -Fq 'den.aspects.shell-git' den/aspects/users/m.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: signing/GPG config is not in shell-git.nix" {
  local non_comment_shell_git
  non_comment_shell_git=$(grep -Ev '^[[:space:]]*#' den/aspects/features/shell-git.nix)
  if printf '%s\n' "$non_comment_shell_git" | grep -Eq 'gitSigningKey|signByDefault|signing\.key|gpg\.program|services\.gpg-agent'; then
    fail 'signing/GPG config found in shell-git.nix — it must stay in gpg.nix'
  fi
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 home-manager base settings" {
  local actual
  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.useGlobalPkgs)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.useUserPackages)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.backupFileExtension)
  assert_equal "$actual" "backup"
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 wayprompt derives from host pkgs" {
  local vm_wayprompt_drv vm_global_wayprompt_drv
  vm_wayprompt_drv=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.wayprompt.package.drvPath)
  vm_global_wayprompt_drv=$(nix_eval_raw .#nixosConfigurations.vm-aarch64._module.args.pkgs.wayprompt.drvPath)
  assert_equal "$vm_wayprompt_drv" "$vm_global_wayprompt_drv"
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 HM git, zsh, EDITOR, stateVersion, git settings" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.sessionVariables.EDITOR)
  assert_equal "$actual" "nvim"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.stateVersion)
  assert_equal "$actual" "18.09"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.init.defaultBranch)
  assert_equal "$actual" "main"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.github.user)
  assert_equal "$actual" "smallstepman"
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 HM programs (oh-my-posh, rbw, pinentry, g alias, git aliases)" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.oh-my-posh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.settings.pinentry \
    'pinentry: toString pinentry')
  [[ "$actual" == *pinentry-wayprompt* ]] \
    || fail "vm-aarch64 rbw pinentry: expected pinentry-wayprompt, got '$actual'"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases.g)
  assert_equal "$actual" "git"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.aliases)
  printf '%s' "$actual" | grep -q '"prettylog"' \
    || fail "vm-aarch64 git aliases missing prettylog; got: $actual"
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 has Linux pbcopy alias" {
  local zsh_aliases
  zsh_aliases=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases)
  printf '%s' "$zsh_aliases" | grep -q '"pbcopy"' \
    || fail "vm-aarch64 zsh shellAliases missing Linux 'pbcopy'; got: $zsh_aliases"
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 home-manager base settings" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.useGlobalPkgs)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.useUserPackages)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.backupFileExtension)
  assert_equal "$actual" "backup"
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 HM git, zsh, EDITOR, stateVersion, DISPLAY" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.sessionVariables.EDITOR)
  assert_equal "$actual" "nvim"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.stateVersion)
  assert_equal "$actual" "18.09"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.sessionVariables.DISPLAY)
  assert_equal "$actual" "nixpkgs-390751"
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 Darwin-specific shell aliases (niks present, pbcopy absent)" {
  local mac_aliases
  mac_aliases=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.shellAliases)
  printf '%s' "$mac_aliases" | grep -q '"niks"' \
    || fail "macbook-pro-m1 zsh shellAliases missing 'niks'; got: $mac_aliases"
  if printf '%s' "$mac_aliases" | grep -q '"pbcopy"'; then
    fail "macbook-pro-m1 zsh shellAliases has Linux-only 'pbcopy'; got: $mac_aliases"
  fi
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 oh-my-posh enabled and gh credential helper enabled" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.oh-my-posh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.gh.gitCredentialHelper.enable)
  assert_equal "$actual" "true"
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 core packages present (bat eza fnm jq rbw ripgrep tig)" {
  local darwin_packages
  darwin_packages=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages)
  for pkg in bat eza fnm jq rbw ripgrep tig; do
    printf '%s' "$darwin_packages" | grep -q -- "-$pkg" \
      || fail "macbook-pro-m1 home.packages missing $pkg"
  done
  if printf '%s' "$darwin_packages" | grep -q -- '-git-credential-github'; then
    fail 'macbook-pro-m1 home.packages should not include git-credential-github'
  fi
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 xdg configFiles (grm, wezterm, activitywatch, kanata)" {
  local actual

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.xdg.configFile \
    'cfg: if cfg ? "grm/repos.yaml" then "true" else "false"')
  assert_equal "$actual" "true"

  actual=$(nix_eval_apply_raw \
    ".#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.xdg.configFile.\"grm/repos.yaml\".source" \
    'source: toString source')
  [[ "$actual" == *dotfiles/common/grm-repos.yaml ]] \
    || fail "macbook-pro-m1 grm/repos.yaml source unexpected: '$actual'"

  for key in 'wezterm/wezterm.lua' 'activitywatch/scripts' 'kanata-tray' 'kanata'; do
    actual=$(nix_eval_apply_raw \
      .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.xdg.configFile \
      "cfg: if cfg ? \"${key}\" then \"true\" else \"false\"")
    assert_equal "$actual" "true" || fail "macbook-pro-m1 missing xdg.configFile.\"${key}\""
  done
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 has ghostty and sentry-cli in packages" {
  local actual

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages \
    'pkgs: if builtins.any (pkg: builtins.match ".*ghostty.*" (pkg.name or "") != null) pkgs then "true" else "false"')
  assert_equal "$actual" "true"

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages \
    'pkgs: if builtins.any (pkg: builtins.match ".*sentry-cli.*" (pkg.name or "") != null) pkgs then "true" else "false"')
  assert_equal "$actual" "true"
}

# bats test_tags=home-manager-core
@test "home-manager-core: wsl home-manager base settings" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.useGlobalPkgs)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.useUserPackages)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#nixosConfigurations.wsl.config.home-manager.backupFileExtension)
  assert_equal "$actual" "backup"
}

# bats test_tags=home-manager-core
@test "home-manager-core: wsl HM git and zsh enabled" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.programs.git.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.programs.zsh.enable)
  assert_equal "$actual" "true"
}

# bats test_tags=home-manager-core
@test "home-manager-core: wsl does not have Darwin-only pinentry alias" {
  local wsl_aliases
  wsl_aliases=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.programs.zsh.shellAliases)
  if printf '%s' "$wsl_aliases" | grep -q '"pinentry"'; then
    fail "wsl zsh shellAliases has Darwin-only 'pinentry'"
  fi
}

# bats test_tags=home-manager-core
@test "home-manager-core: wsl gh credential helper is disabled (Linux uses rbw)" {
  local actual
  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.programs.gh.gitCredentialHelper.enable)
  assert_equal "$actual" "false"
}

# bats test_tags=home-manager-core
@test "home-manager-core: wsl rbw is enabled with pinentry-tty" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.programs.rbw.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_apply_raw \
    .#nixosConfigurations.wsl.config.home-manager.users.m.programs.rbw.settings.pinentry \
    'pinentry: toString pinentry')
  [[ "$actual" == *pinentry-tty* ]] \
    || fail "wsl rbw pinentry: expected pinentry-tty, got '$actual'"
}


# ===========================================================================
# devtools — editors-devtools and ai-tools aspects
# ===========================================================================

# bats test_tags=devtools
@test "devtools: editors-devtools.nix and ai-tools.nix exist" {
  assert_file_exists den/aspects/features/editors-devtools.nix
  assert_file_exists den/aspects/features/ai-tools.nix
}

# bats test_tags=devtools
@test "devtools: editors-devtools.nix owns required packages and programs" {
  grep -Fq 'pkgs.go'                  den/aspects/features/editors-devtools.nix
  grep -Fq 'pkgs.nodejs_22'           den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.doom-emacs'      den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.tmux'            den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.vscode'          den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.lazyvim'         den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.go'              den/aspects/features/editors-devtools.nix
  grep -Fq 'installWritableTmuxMenus' den/aspects/features/editors-devtools.nix
  grep -Fq 'services.emacs'           den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.starship'        den/aspects/features/editors-devtools.nix
  grep -Fq 'programs.zellij'          den/aspects/features/editors-devtools.nix
  grep -Fq 'pkgs.devenv'              den/aspects/features/editors-devtools.nix
  grep -Fq 'pkgs.dust'                den/aspects/features/editors-devtools.nix
  grep -Fq 'pkgs.zellij'              den/aspects/features/editors-devtools.nix
}

# bats test_tags=devtools
@test "devtools: ai-tools.nix owns AI package and program entries" {
  grep -Fq 'pkgs.llm-agents.copilot-cli'             den/aspects/features/ai-tools.nix
  grep -Fq 'programs.opencode'                        den/aspects/features/ai-tools.nix
  grep -Fq 'opencodeAwesome'                          den/aspects/features/ai-tools.nix
  grep -Fq 'ensureOpencodePackageJsonWritable'        den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.agent-of-empires'                    den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.dotagents'                           den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.apm'                                 den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.beads'                    den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.openspec'                 den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.copilot-language-server'  den/aspects/features/ai-tools.nix
  grep -Fq 'opencode/modules/home-manager.nix'        den/aspects/features/ai-tools.nix
}

# bats test_tags=devtools
@test "devtools: user m aspect wires editors-devtools and ai-tools" {
  grep -Fq 'den.aspects.editors-devtools' den/aspects/users/m.nix
  grep -Fq 'den.aspects.ai-tools'         den/aspects/users/m.nix
}

# bats test_tags=devtools
@test "devtools: Task 6 aspects do not contain out-of-scope items" {
  for aspect in den/aspects/features/editors-devtools.nix den/aspects/features/ai-tools.nix; do
    local non_comment
    non_comment=$(grep -Ev '^[[:space:]]*#' "$aspect")
    if printf '%s\n' "$non_comment" | grep -Eq 'projectsRoot|niriDeep'; then
      fail "$aspect contains projectsRoot/niriDeep — must stay in home-manager.nix"
    fi
    if printf '%s\n' "$non_comment" | grep -Eq 'load_plugins'; then
      fail "$aspect contains load_plugins — must stay in home-manager.nix (Task 8)"
    fi
  done
}

# bats test_tags=devtools
@test "devtools: vm-aarch64 doom-emacs, vscode, emacs service, go GOPATH, opencode enabled" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.doom-emacs.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.services.emacs.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.vscode.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.go.env.GOPATH 2>/dev/null || echo "")
  assert_equal "$actual" "Documents/go"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.opencode.enable)
  assert_equal "$actual" "true"
}

# bats test_tags=devtools
@test "devtools: macbook-pro-m1 doom-emacs enabled (services.emacs disabled on Darwin)" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.doom-emacs.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.emacs.enable)
  assert_equal "$actual" "false"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.vscode.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.opencode.enable)
  assert_equal "$actual" "true"
}

# bats test_tags=devtools
@test "devtools: macbook-pro-m1 has copilot-cli and go packages" {
  local mac_packages
  mac_packages=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.packages)
  printf '%s' "$mac_packages" | grep -q 'copilot' \
    || fail "macbook-pro-m1 home.packages missing copilot-cli"
  printf '%s' "$mac_packages" | grep -qE '\-go-[0-9]' \
    || fail "macbook-pro-m1 home.packages missing go"
}

# bats test_tags=devtools
@test "devtools: wsl emacs service enabled and opencode enabled" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.services.emacs.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.home-manager.users.m.programs.opencode.enable)
  assert_equal "$actual" "true"
}


# ===========================================================================
# linux-core — linux-core and secrets aspects
# ===========================================================================

# bats test_tags=linux-core
@test "linux-core: linux-core.nix and secrets.nix exist" {
  assert_file_exists den/aspects/features/linux-core.nix
  assert_file_exists den/aspects/features/secrets.nix
}

# bats test_tags=linux-core
@test "linux-core: linux-core.nix owns required system settings" {
  grep -Fq 'boot.kernelPackages'        den/aspects/features/linux-core.nix
  grep -Fq 'nix.package'                den/aspects/features/linux-core.nix
  grep -Fq 'services.openssh.enable'    den/aspects/features/linux-core.nix
  grep -Fq 'networking.networkmanager'  den/aspects/features/linux-core.nix
  grep -Fq 'programs.nix-ld'            den/aspects/features/linux-core.nix
  grep -Fq 'environment.localBinInPath' den/aspects/features/linux-core.nix
  grep -Fq 'programs.zsh.enable'        den/aspects/features/linux-core.nix
  grep -Fq 'services.flatpak.enable'    den/aspects/features/linux-core.nix
  grep -Fq 'system.stateVersion'        den/aspects/features/linux-core.nix
  grep -Fq 'i18n.defaultLocale'         den/aspects/features/linux-core.nix
  grep -Fq 'security.sudo'              den/aspects/features/linux-core.nix
  grep -Fq 'networking.firewall'        den/aspects/features/linux-core.nix
  grep -Fq 'fonts.fontDir.enable'       den/aspects/features/linux-core.nix
}

# bats test_tags=linux-core
@test "linux-core: secrets.nix owns sops and tailscale settings" {
  grep -Fq 'sops.defaultSopsFile'  den/aspects/features/secrets.nix
  grep -Fq 'sops.age'              den/aspects/features/secrets.nix
  grep -Fq 'tailscale/auth-key'    den/aspects/features/secrets.nix
  grep -Fq 'user/hashed-password'  den/aspects/features/secrets.nix
  grep -Fq 'rbw-config'            den/aspects/features/secrets.nix
  grep -Fq 'services.tailscale'    den/aspects/features/secrets.nix
  grep -Fq 'users.mutableUsers'    den/aspects/features/secrets.nix
}

# bats test_tags=linux-core
@test "linux-core: vm-aarch64 host aspect wires linux-core and secrets" {
  grep -Fq 'den.aspects.linux-core' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'den.aspects.secrets'    den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=linux-core
@test "linux-core: vm-aarch64 host aspect owns host-specific remnants" {
  grep -Fq 'openwebui-local-proxy' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'authorizedKeys'        den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'extraGroups'           den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'sops.hostPubKey'       den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=linux-core
@test "linux-core: secrets.nix does not own sops.hostPubKey" {
  if grep -Ev '^[[:space:]]*#' den/aspects/features/secrets.nix | grep -Fq 'sops.hostPubKey'; then
    fail 'den/aspects/features/secrets.nix should not own sops.hostPubKey'
  fi
}

# bats test_tags=linux-core
@test "linux-core: linux-core.nix does not own wl-clipboard" {
  if grep -Ev '^[[:space:]]*#' den/aspects/features/linux-core.nix | grep -Fq 'wl-clipboard'; then
    fail 'den/aspects/features/linux-core.nix should not own wl-clipboard'
  fi
}

# bats test_tags=linux-core
@test "linux-core: vm-aarch64 system services and settings evaluate correctly" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.services.openssh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.services.tailscale.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.programs.nix-ld.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.environment.localBinInPath)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.users.mutableUsers)
  assert_equal "$actual" "false"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.security.sudo.wheelNeedsPassword)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.networking.networkmanager.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.networking.firewall.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.services.snap.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.sops.age.generateKey)
  assert_equal "$actual" "true"
}

# bats test_tags=linux-core
@test "linux-core: vm-aarch64 users.users.m hashed password and authorized keys" {
  local actual

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.users.users.m.hashedPasswordFile)
  printf '%s' "$actual" | grep -q 'hashed-password' \
    || fail "hashedPasswordFile missing 'hashed-password' token; got '$actual'"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.users.users.m.openssh.authorizedKeys.keyFiles)
  printf '%s' "$actual" | grep -q 'host-authorized-keys' \
    || fail "authorizedKeys.keyFiles missing host-authorized-keys; got '$actual'"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.users.users.m.extraGroups)
  printf '%s' "$actual" | grep -q '"lxd"' \
    || fail "extraGroups missing lxd; got '$actual'"
}

# bats test_tags=linux-core
@test "linux-core: vm-aarch64 sops.defaultSopsFile resolves through generated input" {
  local actual
  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.sops.defaultSopsFile)
  printf '%s' "$actual" | grep -q 'secrets.yaml' \
    || fail "sops.defaultSopsFile does not mention secrets.yaml; got '$actual'"
}


# ===========================================================================
# vm-desktop — linux-desktop and vmware aspects
# ===========================================================================

# bats test_tags=vm-desktop
@test "vm-desktop: linux-desktop.nix and vmware.nix exist" {
  assert_file_exists den/aspects/features/linux-desktop.nix
  assert_file_exists den/aspects/features/vmware.nix
}

# bats test_tags=vm-desktop
@test "vm-desktop: linux-desktop.nix owns desktop stack" {
  grep -Fq 'programs.niri.enable'           den/aspects/features/linux-desktop.nix
  grep -Fq 'services.noctalia-shell.enable' den/aspects/features/linux-desktop.nix
  grep -Fq 'services.greetd'                den/aspects/features/linux-desktop.nix
  grep -Fq 'hardware.bluetooth.enable'      den/aspects/features/linux-desktop.nix
  grep -Fq 'services.keyd'                  den/aspects/features/linux-desktop.nix
  grep -Fq 'i18n.inputMethod'               den/aspects/features/linux-desktop.nix
  grep -Fq 'programs.kitty'                 den/aspects/features/linux-desktop.nix
  grep -Fq 'programs.wayprompt'             den/aspects/features/linux-desktop.nix
  grep -Fq 'programs.noctalia-shell'        den/aspects/features/linux-desktop.nix
  grep -Fq 'programs.librewolf'             den/aspects/features/linux-desktop.nix
  grep -Fq 'home.pointerCursor'             den/aspects/features/linux-desktop.nix
  grep -Fq 'wl-clipboard'                   den/aspects/features/linux-desktop.nix
}

# bats test_tags=vm-desktop
@test "vm-desktop: vmware.nix owns VMware integration settings" {
  grep -Fq 'virtualisation.vmware.guest.enable' den/aspects/features/vmware.nix
  grep -Fq '.host:/Projects'                    den/aspects/features/vmware.nix
  grep -Fq '.host:/nixos-config'                den/aspects/features/vmware.nix
  grep -Fq 'yeetAndYoink.requirePath'           den/aspects/features/vmware.nix
  grep -Fq 'src = yeetAndYoink.root;'           den/aspects/features/vmware.nix
  grep -Fq 'cargoLock.lockFile = yeetAndYoink.requirePath "Cargo.lock";' den/aspects/features/vmware.nix
  grep -Fq 'programs.ssh'                       den/aspects/features/vmware.nix
  grep -Fq 'programs.niri.settings'             den/aspects/features/vmware.nix
  grep -Fq 'DOCKER_CONTEXT'                     den/aspects/features/vmware.nix
  grep -Fq 'NIRI_DEEP_ZELLIJ_BREAK_PLUGIN'      den/aspects/features/vmware.nix
  grep -Fq 'load_plugins'                       den/aspects/features/vmware.nix
  grep -Fq 'uniclip'                            den/aspects/features/vmware.nix
  grep -Fq 'ensureHostDockerContext'             den/aspects/features/vmware.nix
  grep -Fq 'mac-host-docker'                    den/aspects/features/vmware.nix
}

# bats test_tags=vm-desktop
@test "vm-desktop: scripts and docs reference external-input-flake.sh correctly" {
  grep -Fq 'external-input-flake.sh'                           docs/vm.sh
  grep -Fq 'external-input-flake.sh'                           den/aspects/features/shell-git.nix
  grep -Fq 'git+file://$yeet_dir?dir=plugins/zellij-break'    scripts/external-input-flake.sh
  grep -Fq 'YEET_AND_YOINK_INPUT_DIR'                         den/aspects/features/shell-git.nix
}

# bats test_tags=vm-desktop
@test "vm-desktop: vm-aarch64 host aspect wires linux-desktop and vmware" {
  grep -Fq 'den.aspects.linux-desktop' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'den.aspects.vmware'        den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'boot.binfmt.emulatedSystems'          den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'networking.interfaces.enp2s0.useDHCP' den/aspects/hosts/vm-aarch64.nix
  if grep -Fq '../../../machines/hardware/' den/aspects/hosts/vm-aarch64.nix; then
    fail 'den/aspects/hosts/vm-aarch64.nix still imports machines/hardware/*'
  fi
}

# bats test_tags=vm-desktop
@test "vm-desktop: vmware.nix does not own vm-aarch64-specific binfmt/DHCP settings" {
  if grep -Ev '^[[:space:]]*#' den/aspects/features/vmware.nix | grep -Eq 'boot\.binfmt\.emulatedSystems|networking\.interfaces\.enp2s0\.useDHCP'; then
    fail 'den/aspects/features/vmware.nix should not own vm-aarch64-specific binfmt/DHCP settings'
  fi
}

# bats test_tags=vm-desktop
@test "vm-desktop: vm-aarch64 NixOS system settings evaluate correctly" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.programs.niri.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.services.noctalia-shell.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.virtualisation.vmware.guest.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.services.greetd.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw ".#nixosConfigurations.vm-aarch64.config.fileSystems.\"/Users/m/Projects\".device")
  printf '%s' "$actual" | grep -q '.host:/Projects' \
    || fail "fileSystems./Users/m/Projects.device: expected '.host:/Projects', got '$actual'"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.boot.binfmt.emulatedSystems)
  printf '%s' "$actual" | grep -q '"x86_64-linux"' \
    || fail "boot.binfmt.emulatedSystems missing x86_64-linux; got '$actual'"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.boot.initrd.availableKernelModules)
  printf '%s' "$actual" | grep -q '"nvme"' \
    || fail "boot.initrd.availableKernelModules missing nvme; got '$actual'"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.disko.devices.disk.main.content.partitions.root.content.mountpoint)
  assert_equal "$actual" "/"
}

# bats test_tags=vm-desktop
@test "vm-desktop: vm-aarch64 HM desktop settings evaluate correctly" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.kitty.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.ssh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.wayprompt.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.niri.settings.prefer-no-csd)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zellij.settings.load_plugins)
  printf '%s' "$actual" | grep -q 'yeet-and-yoink-zellij-break.wasm' \
    || fail "load_plugins does not contain yeet-and-yoink-zellij-break.wasm; got '$actual'"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.sessionVariables.DOCKER_CONTEXT)
  assert_equal "$actual" "host-mac"
}

# bats test_tags=vm-desktop
@test "vm-desktop: wsl does not inherit VM desktop or VMware features" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.virtualisation.vmware.guest.enable)
  assert_equal "$actual" "false"

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.programs.niri.enable)
  assert_equal "$actual" "false"
}


# ===========================================================================
# darwin — darwin-core, darwin-desktop, homebrew, and launchd aspects
# ===========================================================================

# bats test_tags=darwin
@test "darwin: required aspect files exist" {
  assert_file_exists den/aspects/features/darwin-core.nix
  assert_file_exists den/aspects/features/darwin-desktop.nix
  assert_file_exists den/aspects/features/homebrew.nix
  assert_file_exists den/aspects/features/launchd.nix
}

# bats test_tags=darwin
@test "darwin: aspect files own required settings" {
  grep -Fq 'system.stateVersion = 5;'                den/aspects/features/darwin-core.nix
  grep -Fq 'nix.enable = false;'                     den/aspects/features/darwin-core.nix
  grep -Fq 'services.openssh.enable = true;'         den/aspects/features/darwin-core.nix
  grep -Fq 'openssh.authorizedKeys.keyFiles'          den/aspects/features/darwin-core.nix
  grep -Fq 'system.defaults.CustomUserPreferences'    den/aspects/features/darwin-desktop.nix
  grep -Fq 'services.yabai.enable = true;'           den/aspects/features/darwin-desktop.nix
  grep -Fq 'services.skhd = {'                       den/aspects/features/darwin-desktop.nix
  grep -Fq 'homebrew.enable = true;'                 den/aspects/features/homebrew.nix
  grep -Fq '../../../dotfiles/common/opencode/modules/darwin.nix' den/aspects/features/launchd.nix
  grep -Fq 'launchd.user.agents.uniclip'             den/aspects/features/launchd.nix
  grep -Fq 'AW_IMPORT_SRC'                           den/aspects/features/launchd.nix
}

# bats test_tags=darwin
@test "darwin: macbook-pro-m1 host aspect wires all darwin aspects" {
  grep -Fq 'den.aspects.darwin-core'    den/aspects/hosts/macbook-pro-m1.nix
  grep -Fq 'den.aspects.darwin-desktop' den/aspects/hosts/macbook-pro-m1.nix
  grep -Fq 'den.aspects.homebrew'       den/aspects/hosts/macbook-pro-m1.nix
  grep -Fq 'den.aspects.launchd'        den/aspects/hosts/macbook-pro-m1.nix
}

# bats test_tags=darwin
@test "darwin: macbook-pro-m1 Darwin system settings evaluate correctly" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.nix.enable)
  assert_equal "$actual" "false"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.services.openssh.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.services.openssh.extraConfig)
  printf '%s' "$actual" | grep -Fq 'ListenAddress 192.168.130.1' \
    || fail "services.openssh.extraConfig missing ListenAddress 192.168.130.1"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.homebrew.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser)
  assert_equal "$actual" "m"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.system.stateVersion)
  assert_equal "$actual" "5"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.system.defaults.CustomUserPreferences.\"com.apple.finder\".AppleShowAllFiles)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.services.yabai.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.services.skhd.enable)
  assert_equal "$actual" "true"
}

# bats test_tags=darwin
@test "darwin: uniclip overlay package present in both darwin and vm" {
  local actual

  actual=$(nix_eval_apply_raw .#darwinConfigurations.macbook-pro-m1.pkgs 'pkgs: if pkgs ? uniclip then "yes" else "no"')
  assert_equal "$actual" "yes"

  actual=$(nix_eval_apply_raw .#nixosConfigurations.vm-aarch64.pkgs 'pkgs: if pkgs ? uniclip then "yes" else "no"')
  assert_equal "$actual" "yes"
}

# bats test_tags=darwin
@test "darwin: Darwin launchd agents (uniclip, opencode-serve, opencode-web) present" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents.uniclip.serviceConfig.RunAtLoad)
  assert_equal "$actual" "true"

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents \
    'agents: if agents ? "opencode-serve" then "yes" else "no"')
  assert_equal "$actual" "yes"

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents \
    'agents: if agents ? "opencode-web" then "yes" else "no"')
  assert_equal "$actual" "yes"
}


# ===========================================================================
# wsl — upstream WSL activation with host-owned repo policy
# ===========================================================================

# bats test_tags=wsl
@test "wsl: host aspect exists and legacy feature aspect is removed" {
  assert_file_exists den/aspects/hosts/wsl.nix
  assert [ ! -e den/aspects/features/wsl.nix ]
}

# bats test_tags=wsl
@test "wsl: den/aspects/hosts/wsl.nix owns repo-specific WSL settings only" {
  grep -Fq 'wsl.wslConf.automount.root = "/mnt";' den/aspects/hosts/wsl.nix
  grep -Fq 'wsl.startMenuLaunchers = true;' den/aspects/hosts/wsl.nix
  grep -Fq 'nix.package = pkgs.nixVersions.latest;' den/aspects/hosts/wsl.nix
  grep -Fq 'keep-outputs = true' den/aspects/hosts/wsl.nix
  grep -Fq 'keep-derivations = true' den/aspects/hosts/wsl.nix
  grep -Fq 'nix.settings.experimental-features = [ "nix-command" "flakes" ];' den/aspects/hosts/wsl.nix
  grep -Fq 'system.stateVersion = "23.05";' den/aspects/hosts/wsl.nix
}

# bats test_tags=wsl
@test "wsl: den/aspects/hosts/wsl.nix does not own upstream module import or defaultUser" {
  if grep -Eq 'defaultUser[[:space:]]*=' den/aspects/hosts/wsl.nix; then
    fail 'den/aspects/hosts/wsl.nix should not redefine wsl.defaultUser'
  fi
  if grep -Fq 'inputs.nixos-wsl.nixosModules.wsl' den/aspects/hosts/wsl.nix; then
    fail 'den/aspects/hosts/wsl.nix should not import inputs.nixos-wsl.nixosModules.wsl'
  fi
}

# bats test_tags=wsl
@test "wsl: wsl config evaluates correctly" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.wsl.enable)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#nixosConfigurations.wsl.config.wsl.defaultUser)
  assert_equal "$actual" "m"

  actual=$(nix_eval_raw .#nixosConfigurations.wsl.config.wsl.wslConf.automount.root)
  assert_equal "$actual" "/mnt"

  actual=$(nix_eval_json .#nixosConfigurations.wsl.config.wsl.startMenuLaunchers)
  assert_equal "$actual" "true"

  local nix_version expected_version
  nix_version=$(nix_eval_raw .#nixosConfigurations.wsl.config.nix.package.version)
  expected_version=$(nix_eval_raw .#nixosConfigurations.wsl.pkgs.nixVersions.latest.version)
  assert_equal "$nix_version" "$expected_version"

  actual=$(nix_eval_json '.#nixosConfigurations.wsl.config.nix.settings."experimental-features"')
  printf '%s' "$actual" | grep -q '"nix-command"' \
    || fail "nix.settings.experimental-features missing nix-command; got $actual"
  printf '%s' "$actual" | grep -q '"flakes"' \
    || fail "nix.settings.experimental-features missing flakes; got $actual"

  actual=$(nix_eval_raw .#nixosConfigurations.wsl.config.nix.extraOptions)
  printf '%s' "$actual" | grep -Fq 'keep-outputs = true' \
    || fail "nix.extraOptions missing keep-outputs = true"
  printf '%s' "$actual" | grep -Fq 'keep-derivations = true' \
    || fail "nix.extraOptions missing keep-derivations = true"

  actual=$(nix_eval_raw .#nixosConfigurations.wsl.config.system.stateVersion)
  assert_equal "$actual" "23.05"
}

# bats test_tags=wsl
@test "wsl: wsl.enable is defined by den provides/wsl.nix (provenance)" {
  local defs
  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.wsl.enable.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'provides/wsl.nix' \
    || fail "wsl.enable not defined by den provides/wsl.nix; got: $defs"
}

# bats test_tags=wsl
@test "wsl: wsl.defaultUser is defined by den provides/wsl.nix (provenance)" {
  local defs
  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.wsl.defaultUser.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'provides/wsl.nix' \
    || fail "wsl.defaultUser not defined by den provides/wsl.nix; got: $defs"
}

# bats test_tags=wsl
@test "wsl: repo-specific WSL settings are defined by den/aspects/hosts/wsl.nix (provenance)" {
  local defs

  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.wsl.startMenuLaunchers.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'den/aspects/hosts/wsl.nix' \
    || fail "wsl.startMenuLaunchers not defined by den/aspects/hosts/wsl.nix; got: $defs"

  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.nix.package.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'den/aspects/hosts/wsl.nix' \
    || fail "nix.package not defined by den/aspects/hosts/wsl.nix; got: $defs"

  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.nix.extraOptions.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'den/aspects/hosts/wsl.nix' \
    || fail "nix.extraOptions not defined by den/aspects/hosts/wsl.nix; got: $defs"

  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.system.stateVersion.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'den/aspects/hosts/wsl.nix' \
    || fail "system.stateVersion not defined by den/aspects/hosts/wsl.nix; got: $defs"
}


# ===========================================================================
# gpg — gpg aspect owns GPG/signing configuration
# ===========================================================================

# bats test_tags=gpg
@test "gpg: den/aspects/features/gpg.nix exists" {
  assert_file_exists den/aspects/features/gpg.nix
}

# bats test_tags=gpg
@test "gpg: gpg.nix uses den-native host context (isVM/isDarwin, not currentSystemName)" {
  grep -Fq 'isVM'     den/aspects/features/gpg.nix
  grep -Fq 'isDarwin' den/aspects/features/gpg.nix
  if grep -Fq 'currentSystemName' den/aspects/features/gpg.nix; then
    fail 'gpg.nix still uses legacy currentSystemName — must use den host context (isVM/isDarwin)'
  fi
}

# bats test_tags=gpg
@test "gpg: gpg.nix contains the vm-aarch64 signing key" {
  grep -Fq 'vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";' den/aspects/features/gpg.nix
}

# bats test_tags=gpg
@test "gpg: gpg.nix guards VM-only features with isVM" {
  grep -Fq '(lib.optionalString isVM "allow-preset-passphrase")' den/aspects/features/gpg.nix
  grep -Fq 'lib.optionals isVM ['                                den/aspects/features/gpg.nix
  grep -Fq 'systemd.user.services.gpg-preset-passphrase-login = lib.mkIf isVM {' den/aspects/features/gpg.nix
}

# bats test_tags=gpg
@test "gpg: gpg.nix helper script implementation is correct" {
  grep -Fq 'printf '\''%s'\'' "$passphrase" |' den/aspects/features/gpg.nix
  grep -Fq 'mapfile -t keygrips < <('          den/aspects/features/gpg.nix
  # The Nix file uses ''${...} escaping inside ''...'' string literals.
  grep -Fq "for keygrip in \"''\${keygrips[@]}\"; do" den/aspects/features/gpg.nix
  grep -Fq 'gpg-preset-passphrase --preset "$keygrip"' den/aspects/features/gpg.nix
  if grep -Fq -- '--passphrase-fd' den/aspects/features/gpg.nix; then
    fail 'gpg.nix helper script still uses unsupported --passphrase-fd'
  fi
  if grep -Fq -- '--passphrase "$passphrase"' den/aspects/features/gpg.nix; then
    fail 'gpg.nix helper script should not expose the passphrase via command-line arguments'
  fi
  if grep -Fq "\$1 == \"grp\" { print \$10; exit }" den/aspects/features/gpg.nix; then
    fail 'gpg.nix helper script still assumes the first grp line is the only relevant keygrip'
  fi
}

# bats test_tags=gpg
@test "gpg: gpg.nix systemd service has retry settings" {
  grep -Fq 'Restart = "on-failure";' den/aspects/features/gpg.nix
  grep -Fq 'RestartSec = 30;'        den/aspects/features/gpg.nix
}

# bats test_tags=gpg
@test "gpg: vm-aarch64 gpg-agent allows preset passphrases; macbook-pro-m1 does not" {
  local vm_extra_config mac_extra_config

  vm_extra_config=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.services.gpg-agent.extraConfig)
  [[ "$vm_extra_config" == *allow-preset-passphrase* ]] \
    || fail 'vm-aarch64 gpg-agent does not allow preset passphrases'

  mac_extra_config=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.gpg-agent.extraConfig)
  [[ "$mac_extra_config" != *allow-preset-passphrase* ]] \
    || fail 'macbook-pro-m1 unexpectedly allows preset passphrases'
  [[ "$mac_extra_config" == *pinentry-program* ]] \
    || fail 'macbook-pro-m1 lost pinentry-program configuration'
  [[ "$mac_extra_config" != *ignore-cache-for-signing* ]] \
    || fail 'macbook-pro-m1 should use short agent TTLs instead of ignore-cache-for-signing'
}

# bats test_tags=gpg
@test "gpg: macbook-pro-m1 gpg-agent cache TTLs are 1 second" {
  local actual

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.gpg-agent.defaultCacheTtl)
  assert_equal "$actual" "1"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.services.gpg-agent.maxCacheTtl)
  assert_equal "$actual" "1"
}

# bats test_tags=gpg
@test "gpg: vm-aarch64 helper script package and systemd service are present" {
  local actual

  actual=$(nix_generated_eval --json \
    --apply 'pkgs: builtins.any (pkg: (pkg.name or "") == "gpg-preset-passphrase-login") pkgs' \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.packages)
  assert_equal "$actual" "true"

  actual=$(nix_generated_eval --json \
    --apply 'services: services ? "gpg-preset-passphrase-login"' \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services)
  assert_equal "$actual" "true"
}

# bats test_tags=gpg
@test "gpg: vm-aarch64 systemd user service configuration is correct" {
  local actual

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.Type)
  assert_equal "$actual" "oneshot"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.ExecStart)
  [[ "$actual" == *gpg-preset-passphrase-login* ]] \
    || fail 'vm-aarch64 systemd user service does not invoke the helper script'

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.Restart)
  assert_equal "$actual" "on-failure"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Service.RestartSec)
  assert_equal "$actual" "30"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Unit.After)
  [[ "$actual" == *default.target* ]] \
    || fail 'vm-aarch64 systemd user service is not ordered after login'
  [[ "$actual" == *rbw-config.service* ]] \
    || fail 'vm-aarch64 systemd user service no longer waits for rbw config'

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services.gpg-preset-passphrase-login.Install.WantedBy)
  [[ "$actual" == *default.target* ]] \
    || fail 'vm-aarch64 systemd user service is not enabled for login-time startup'
}

# bats test_tags=gpg
@test "gpg: macbook-pro-m1 does not define the gpg-preset-passphrase-login systemd service" {
  local mac_service_present
  mac_service_present=$(nix_generated_eval --json \
    --apply 'services: services ? "gpg-preset-passphrase-login"' \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.systemd.user.services)
  assert_equal "$mac_service_present" "false"
}

# bats test_tags=gpg
@test "gpg: git signing keys are configured correctly on vm-aarch64 and macbook-pro-m1" {
  local actual

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.signing.key)
  assert_equal "$actual" "071F6FE39FC26713930A702401E5F9A947FA8F5C"

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.signing.signByDefault)
  assert_equal "$actual" "true"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.signing.key)
  assert_equal "$actual" "9317B542250D33B34C41F62831D3B9C9754C0F5B"

  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.signing.signByDefault)
  assert_equal "$actual" "true"
}

# bats test_tags=gpg
@test "gpg: git gpg.program is set to gpg on vm-aarch64 and homebrew gpg on macbook-pro-m1" {
  local actual

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.gpg.program)
  [[ "$actual" == *gpg* ]] \
    || fail "vm-aarch64 git gpg.program '$actual' does not reference gpg"

  actual=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.git.settings.gpg.program)
  assert_equal "$actual" "/opt/homebrew/bin/gpg"
}


# ===========================================================================
# generated-input — wrapper flake design integrity
# ===========================================================================

# bats test_tags=generated-input
@test "generated-input: generated/ artifacts are not tracked in git" {
  local tracked_generated
  tracked_generated=$(git ls-files 'generated/*')
  assert [ -z "$tracked_generated" ] || fail "generated/ artifacts still tracked: $tracked_generated"
}

# bats test_tags=generated-input
@test "generated-input: sentinel placeholder files are not tracked in git" {
  for sentinel in \
    .generated-input-sentinel/.keep \
    .yeet-and-yoink-input-sentinel/.keep; do
    if git ls-files --error-unmatch "$sentinel" >/dev/null 2>&1; then
      if git diff --name-only --diff-filter=D -- "$sentinel" | grep -q . \
        || git diff --cached --name-only --diff-filter=D -- "$sentinel" | grep -q .; then
        :
      else
        fail "sentinel placeholder is still tracked: $sentinel"
      fi
    fi
  done
}

# bats test_tags=generated-input
@test "generated-input: tests.bats does not use --impure" {
  if rg -n 'nix_generated_eval[[:space:]]+\-\-impure|nix[[:space:]].*\-\-impure' tests.bats >/dev/null; then
    fail 'tests.bats still relies on --impure instead of explicit generated/yeet inputs'
  fi
}

# bats test_tags=generated-input
@test "generated-input: flake.nix does not contain sentinel input declarations" {
  if grep -Fq 'inputs.generated = {' flake.nix; then
    fail 'flake.nix must not contain a sentinel generated input declaration'
  fi
  if grep -Fq 'inputs.yeetAndYoink = {' flake.nix; then
    fail 'flake.nix must not contain a sentinel yeetAndYoink input declaration'
  fi
}

# bats test_tags=generated-input
@test "generated-input: required scripts and files exist" {
  assert_file_exists scripts/external-input-flake.sh
  assert_file_exists den/mk-config-outputs.nix
}

# bats test_tags=generated-input
@test "generated-input: flake.nix exports lib.mkOutputs for wrapper flakes" {
  grep -Fq 'lib.mkOutputs' flake.nix
}

# bats test_tags=generated-input
@test "generated-input: tests.bats uses mk_wrapper_flake" {
  grep -Fq 'mk_wrapper_flake' tests.bats
}

# bats test_tags=generated-input
@test "generated-input: tests.bats does not hardcode the home-m yeet-and-yoink fallback" {
  # Split the path so the literal string doesn't appear in this test body
  # and cause a false self-match.
  local bad_pfx bad_sfx
  bad_pfx='/home/m'
  bad_sfx='/Projects/yeet-and-yoink'
  if rg -n "${bad_pfx}${bad_sfx}" tests.bats >/dev/null; then
    fail "tests.bats must not fall back to ${bad_pfx}${bad_sfx}"
  fi
}

# bats test_tags=generated-input
@test "generated-input: den aspects do not use repo-relative generated/ paths" {
  if rg -n '../../../generated/' \
    den/aspects/features/secrets.nix \
    den/aspects/features/darwin-core.nix \
    den/aspects/hosts/vm-aarch64.nix >/dev/null; then
    fail 'den aspects still read repo-relative generated/ paths'
  fi
}

# bats test_tags=generated-input
@test "generated-input: docs reference external-input-flake.sh" {
  grep -Fq 'external-input-flake.sh' docs/macbook.sh
  grep -Fq 'external-input-flake.sh' docs/vm.sh
  grep -Fq 'external-input-flake.sh' den/aspects/features/shell-git.nix
}

# bats test_tags=generated-input
@test "generated-input: AGENTS.md documents the wrapper flake approach" {
  if rg -n -- '--impure' AGENTS.md >/dev/null; then
    fail 'AGENTS.md must not document --impure for flake-aware commands'
  fi
  grep -Fq 'external-input-flake.sh' AGENTS.md
  grep -Fq 'scripts/external-input-flake.sh' AGENTS.md
  grep -Fq 'path:$WRAPPER' AGENTS.md
}

# bats test_tags=generated-input
@test "generated-input: docs scripts have default_nix_config_dir helper" {
  grep -Fq 'default_nix_config_dir()' docs/macbook.sh
  grep -Fq 'default_nix_config_dir()' docs/vm.sh
}

# bats test_tags=generated-input
@test "generated-input: vmware aspect and vm.sh wire the nixos-generated shared folder" {
  grep -Fq '.host:/nixos-generated' den/aspects/features/vmware.nix
  grep -Fq 'guestName = "nixos-generated"' docs/vm.sh
  grep -Fq 'vmrun -T fusion setSharedFolderState "$vmx" "$share_name" "$host_path" writable' docs/vm.sh
  grep -Fq 'vmrun -T fusion addSharedFolder "$vmx" "$share_name" "$host_path"' docs/vm.sh
  grep -Fq 'vm_ensure_required_shared_folders "$existing_vmx"' docs/vm.sh
  grep -Fq 'vm_ensure_required_shared_folders "$vmx"' docs/vm.sh
}

# bats test_tags=generated-input
@test "generated-input: sops.defaultSopsFile resolves through the external generated input" {
  local actual
  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.sops.defaultSopsFile)
  printf '%s' "$actual" | grep -q 'secrets.yaml' \
    || fail "sops.defaultSopsFile did not resolve through the external generated input; got: $actual"
}


# ===========================================================================
# bats-package — bats with libraries is wired at the system level
# ===========================================================================

# bats test_tags=bats-package
@test "bats-package: pkgs.bats is not in editors-devtools home.packages" {
  # bats must be a system-level package (with wired BATS_LIB_PATH), not a
  # bare user-level entry in editors-devtools.
  if grep -Eq '^[[:space:]]*pkgs\.bats\b' den/aspects/features/editors-devtools.nix; then
    fail 'pkgs.bats still in editors-devtools home.packages — must be system-level with bats.withLibraries'
  fi
}

# bats test_tags=bats-package
@test "bats-package: linux-core.nix provides bats with libraries at system level" {
  grep -Fq 'bats.withLibraries' den/aspects/features/linux-core.nix
  grep -Fq 'bats-support' den/aspects/features/linux-core.nix
  grep -Fq 'bats-assert'  den/aspects/features/linux-core.nix
  grep -Fq 'bats-file'    den/aspects/features/linux-core.nix
}

# bats test_tags=bats-package
@test "bats-package: darwin-core.nix provides bats with libraries at system level" {
  grep -Fq 'bats.withLibraries' den/aspects/features/darwin-core.nix
  grep -Fq 'bats-support' den/aspects/features/darwin-core.nix
  grep -Fq 'bats-assert'  den/aspects/features/darwin-core.nix
  grep -Fq 'bats-file'    den/aspects/features/darwin-core.nix
}

# bats test_tags=bats-package
@test "bats-package: wsl.nix provides bats with libraries at system level" {
  grep -Fq 'bats.withLibraries' den/aspects/hosts/wsl.nix
  grep -Fq 'bats-support' den/aspects/hosts/wsl.nix
  grep -Fq 'bats-assert'  den/aspects/hosts/wsl.nix
  grep -Fq 'bats-file'    den/aspects/hosts/wsl.nix
}

# bats test_tags=bats-package
@test "bats-package: linux-core.nix provides GNU parallel for bats --jobs" {
  grep -Eq '^[[:space:]]+parallel([[:space:]]|$)' den/aspects/features/linux-core.nix
}

# bats test_tags=bats-package
@test "bats-package: darwin-core.nix provides GNU parallel for bats --jobs" {
  grep -Eq '^[[:space:]]+parallel([[:space:]]|$)' den/aspects/features/darwin-core.nix
}

# bats test_tags=bats-package
@test "bats-package: wsl.nix provides GNU parallel for bats --jobs" {
  grep -Eq '^[[:space:]]+pkgs\.parallel([[:space:]]|$)' den/aspects/hosts/wsl.nix
}
