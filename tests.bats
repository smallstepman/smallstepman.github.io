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
# yeetnyoink inputs via a temporary wrapper flake.
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
  if grep -Fq 'options.vmware.enable' den/default.nix; then
    fail 'vmware.enable schema should be removed from den/default.nix (Task 7)'
  fi
  if grep -Fq 'options.graphical.enable' den/default.nix; then
    fail 'graphical.enable schema should be removed from den/default.nix (Task 7)'
  fi
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
  if grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.vmware.enable = true' den/hosts.nix; then
    fail 'den/hosts.nix should not contain vmware.enable (removed in Task 7)'
  fi
  if grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.graphical.enable = true' den/hosts.nix; then
    fail 'den/hosts.nix should not contain graphical.enable (removed in Task 7)'
  fi
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
  assert_file_exists den/aspects/features/shell.nix
  assert_file_exists den/aspects/features/git.nix
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
  grep -Fq 'programs.git = {' den/aspects/features/git.nix
  grep -Fq 'programs.zsh = {' den/aspects/features/shell.nix
  grep -Fq 'programs.oh-my-posh = {' den/aspects/features/shell.nix
  grep -Fq 'programs.direnv = {' den/aspects/features/shell.nix
  grep -Fq 'programs.atuin = {' den/aspects/features/shell.nix
  grep -Fq 'programs.zoxide = {' den/aspects/features/shell.nix
  grep -Fq 'programs.gh = {' den/aspects/features/git.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: shell-git.nix sets EDITOR session variable" {
  grep -Fq 'EDITOR' den/aspects/features/shell.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: home-base stays shared while platform HM config lives with platform aspects" {
  grep -Fq '"grm/repos.yaml"' den/aspects/features/home-base.nix
  if grep -Fq 'programs.rbw = lib.mkIf isLinux' den/aspects/features/home-base.nix; then
    fail 'home-base.nix still owns Linux rbw config'
  fi
  if grep -Fq 'ghostty-bin' den/aspects/features/home-base.nix; then
    fail 'home-base.nix still owns Darwin packages'
  fi
  if grep -Fq '"wezterm/wezterm.lua"' den/aspects/features/home-base.nix; then
    fail 'home-base.nix still owns Darwin xdg config'
  fi
  grep -Fq 'programs.rbw = lib.mkIf isLinux' den/aspects/features/git.nix
  grep -Fq 'ghostty-bin' den/aspects/features/darwin-core.nix
  grep -Fq '"wezterm/wezterm.lua"' den/aspects/features/darwin-core.nix
  grep -Fq 'den.aspects.home-base' den/aspects/users/m.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: shell-git includes g = git alias" {
  grep -Eq '(^|[[:space:]])g[[:space:]]*=[[:space:]]*"git";' den/aspects/features/shell.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: macbook-pro-m1 enables zsh AUTO_CD for bare-path enter" {
  actual=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.autocd)

  [ "$actual" = "true" ] \
    || fail "macbook-pro-m1 should enable zsh autocd; got: $actual"
}

# bats test_tags=home-manager-core
@test "home-manager-core: zsh manydots does not wrap accept-line" {
  if grep -Eq 'manydots-magic\.(rewrite-buffer|accept-line)|manydots-magic\.orig\.accept-line' dotfiles/common/zsh-manydot.sh; then
    fail "zsh-manydot.sh should not implement custom accept-line/autocd rewriting"
  fi
}

# bats test_tags=home-manager-core
@test "home-manager-core: user m aspect includes shell and git" {
  grep -Fq 'den.aspects.shell' den/aspects/users/m.nix
  grep -Fq 'den.aspects.git'   den/aspects/users/m.nix
}

# bats test_tags=home-manager-core
@test "home-manager-core: git.nix owns GPG and signing config" {
  grep -Fq 'programs.gpg.enable' den/aspects/features/git.nix
  grep -Fq 'services.gpg-agent'  den/aspects/features/git.nix
  grep -Fq 'signing.signByDefault = true' den/aspects/features/git.nix
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

  actual=$(nix_eval_apply_raw .#nixosConfigurations.vm-aarch64.config.home-manager.backupCommand 'cmd: toString cmd')
  [[ "$actual" == *home-manager-rotate-backup ]] \
    || fail "vm-aarch64 backupCommand unexpected: '$actual'"
}

# bats test_tags=home-manager-core
@test "home-manager-core: backup command rotates stale backups" {
  local backup_cmd tmpdir target

  run nix_generated_build --quiet --no-link .#nixosConfigurations.vm-aarch64.config.home-manager.backupCommand
  assert_success
  backup_cmd=$(nix_eval_apply_raw .#nixosConfigurations.vm-aarch64.config.home-manager.backupCommand 'cmd: toString cmd')
  [[ "$backup_cmd" == *home-manager-rotate-backup ]] \
    || fail "vm-aarch64 backupCommand unexpected: '$backup_cmd'"

  tmpdir=$(mktemp -d)
  target="$tmpdir/wezterm.lua"

  printf 'first\n' > "$target"
  run env HOME_MANAGER_BACKUP_EXT=backup "$backup_cmd" "$target"
  assert_success
  assert_file_not_exists "$target"
  assert_file_exists "$target.backup"
  assert_file_contains "$target.backup" "first"

  printf 'stale\n' > "$target.backup"
  printf 'second\n' > "$target"
  run env HOME_MANAGER_BACKUP_EXT=backup "$backup_cmd" "$target"
  assert_success
  assert_file_not_exists "$target"
  assert_file_contains "$target.backup" "stale"
  assert_file_exists "$target.backup.1"
  assert_file_contains "$target.backup.1" "second"

  rm -rf "$tmpdir"
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
@test "home-manager-core: vm-aarch64 and macbook-pro-m1 expose niks-worktree" {
  local vm_alias darwin_alias

  vm_alias=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases."niks-worktree")
  [[ "$vm_alias" == /nix/store/*/bin/niks-worktree* ]] \
    || fail "vm-aarch64 should expose a store-backed niks-worktree command, got '$vm_alias'"

  darwin_alias=$(nix_eval_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.shellAliases."niks-worktree")
  [[ "$darwin_alias" == /nix/store/*/bin/niks-worktree* ]] \
    || fail "macbook-pro-m1 should expose a store-backed niks-worktree command, got '$darwin_alias'"
}

# bats test_tags=home-manager-core
@test "home-manager-core: niks-worktree command knows platform repo roots and worktrees" {
  local vm_drv darwin_drv

  vm_drv=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases."niks-worktree" \
    'alias: builtins.head (builtins.attrNames (builtins.getContext alias))')
  darwin_drv=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.programs.zsh.shellAliases."niks-worktree" \
    'alias: builtins.head (builtins.attrNames (builtins.getContext alias))')

  run python - "$vm_drv" "$darwin_drv" <<'PY'
import json
import subprocess
import sys

vm_drv, darwin_drv = sys.argv[1:3]

def derivation_text(drv: str) -> str:
    payload = json.loads(
        subprocess.run(
            ["nix", "derivation", "show", drv],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    return next(iter(payload["derivations"].values()))["env"]["text"]

vm_text = derivation_text(vm_drv)
darwin_text = derivation_text(darwin_drv)

checks = [
    ("/nixos-config", vm_text, "vm niks-worktree should target /nixos-config"),
    ("~/.config/nix", darwin_text, "darwin niks-worktree should target ~/.config/nix"),
    (".worktrees", vm_text, "vm niks-worktree should scan .worktrees"),
    (".worktrees", darwin_text, "darwin niks-worktree should scan .worktrees"),
    ("/dev/tty", vm_text, "vm niks-worktree should reattach to /dev/tty for interactive selection"),
    ("/dev/tty", darwin_text, "darwin niks-worktree should reattach to /dev/tty for interactive selection"),
]

for needle, haystack, message in checks:
    if needle not in haystack:
        print(message, file=sys.stderr)
        sys.exit(1)

if "fzf" not in vm_text or "select " not in vm_text:
    print("vm niks-worktree should prefer fzf and fall back to shell select", file=sys.stderr)
    sys.exit(1)

if "fzf" not in darwin_text or "select " not in darwin_text:
    print("darwin niks-worktree should prefer fzf and fall back to shell select", file=sys.stderr)
    sys.exit(1)
PY
  assert_success || fail "niks-worktree derivation does not encode the expected platform/worktree selector behavior"
}

# bats test_tags=home-manager-core
@test "vm: vm-aarch64 evaluated rbw pinentry derivation encodes touchid bridge fallback" {
  local actual actual_drv

  actual=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.settings.pinentry \
    'pinentry: toString pinentry')

  [[ "$actual" == /nix/store/*/bin/* ]] \
    || fail "vm-aarch64 rbw pinentry should evaluate to a store-backed wrapper path, got '$actual'"

  actual_drv=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.settings.pinentry \
    'pinentry: builtins.head (builtins.attrNames (builtins.getContext (toString pinentry)))')

  # Check semantic derivation markers so the contract survives wrapper refactors
  # and equivalent Nix rewrites that keep the same bridge/fallback behavior.
  run python - "$actual" "$actual_drv" <<'PY'
import subprocess
import sys

actual, drv = sys.argv[1:3]
proc = subprocess.run(
    ["nix", "derivation", "show", drv],
    check=True,
    capture_output=True,
    text=True,
)
payload = proc.stdout.lower()

bridge_markers = ("pinentry-touchid", "touchid", "broker")
fallback_markers = ("pinentry-wayprompt", "pinentry-tty", "fallback")

if not any(marker in payload for marker in bridge_markers):
    print(
        f"evaluated rbw pinentry derivation for {actual!r} does not encode a macOS touchid bridge marker",
        file=sys.stderr,
    )
    sys.exit(1)

if not any(marker in payload for marker in fallback_markers):
    print(
        f"evaluated rbw pinentry derivation for {actual!r} does not encode a local fallback marker",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  assert_success \
    || fail "vm-aarch64 rbw pinentry should evaluate to a derivation payload that references both the macOS touchid bridge and a local fallback, got '$actual' via '$actual_drv'"

  # Secondary anti-regression checks: the VM host and secrets aspect should not
  # own direct rbw pinentry wiring, regardless of the exact Nix spelling used.
  if rg -n 'programs\.rbw\.settings\.pinentry\s*=' den/aspects/hosts/vm-aarch64.nix >/dev/null; then
    fail 'vm-aarch64 host config still owns a direct rbw pinentry assignment'
  fi

  if rg -n -- '--arg\s+pinentry\b' den/aspects/features/secrets.nix >/dev/null; then
    fail 'secrets.nix still writes rbw pinentry directly into config.json'
  fi
}

# bats test_tags=home-manager-core
@test "vm: vm-aarch64 touchid bridge waits for a slow broker response after connecting" {
  local actual_drv

  actual_drv=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.rbw.settings.pinentry \
    'pinentry: builtins.head (builtins.attrNames (builtins.getContext (toString pinentry)))')

  run python - "$actual_drv" <<'PY'
import importlib.machinery
import importlib.util
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

(drv,) = sys.argv[1:]
payload = json.loads(
    subprocess.run(
        ["nix", "derivation", "show", drv],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
)
script_text = next(iter(payload["derivations"].values()))["env"]["text"]

with tempfile.TemporaryDirectory(prefix="touchid-bridge-script-") as script_dir, tempfile.TemporaryDirectory(
    prefix="touchid-broker-"
) as sock_dir:
    script_path = Path(script_dir) / "bridge.py"
    script_path.write_text(script_text)

    loader = importlib.machinery.SourceFileLoader("bridge_module", str(script_path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)

    sock_path = os.path.join(sock_dir, "broker.sock")
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    server.listen(1)

    request_seen = []
    server_error = []

    def serve():
        try:
            conn, _ = server.accept()
            with conn:
                request = b""
                while not request.endswith(b"\n"):
                    chunk = conn.recv(4096)
                    if not chunk:
                        raise RuntimeError("client closed before broker request completed")
                    request += chunk
                request_seen.append(request)
                time.sleep(3.0)
                conn.sendall(json.dumps({"ok": True, "secret": "touchid-secret"}).encode("utf-8") + b"\n")
        except Exception as exc:
            server_error.append(repr(exc))
        finally:
            server.close()

    thread = threading.Thread(target=serve)
    thread.start()

    module.BROKER_SOCKET = sock_path

    def forbidden_popen(*args, **kwargs):
        raise RuntimeError("fallback invoked while broker stayed connected")

    module.subprocess.Popen = forbidden_popen

    stdin = io.StringIO("GETPIN\nBYE\n")
    stdout = io.StringIO()
    stderr = io.StringIO()
    old_stdin, old_stdout, old_stderr = sys.stdin, sys.stdout, sys.stderr
    start = time.monotonic()
    try:
        sys.stdin, sys.stdout, sys.stderr = stdin, stdout, stderr
        rc = module.main()
    finally:
        elapsed = time.monotonic() - start
        sys.stdin, sys.stdout, sys.stderr = old_stdin, old_stdout, old_stderr
        thread.join(timeout=10)

    if thread.is_alive():
        print("fake broker thread did not finish", file=sys.stderr)
        sys.exit(1)

    if server_error:
        print(f"fake broker failed: {server_error}", file=sys.stderr)
        sys.exit(1)

    if request_seen != [b'{"op":"get-secret"}\n']:
        print(f"unexpected broker request: {request_seen!r}", file=sys.stderr)
        sys.exit(1)

    if rc != 0:
        print(f"bridge exited with rc={rc}", file=sys.stderr)
        sys.exit(1)

    output = stdout.getvalue()
    if "D touchid-secret\nOK\n" not in output:
        print(f"bridge did not emit the broker secret, got: {output!r}", file=sys.stderr)
        sys.exit(1)

    if elapsed < 2.5:
        print(f"bridge returned too quickly for the delayed broker response: {elapsed:.3f}s", file=sys.stderr)
        sys.exit(1)
PY
  assert_success \
    || fail 'vm-aarch64 touchid bridge should keep waiting for a connected broker instead of falling back after the short connect timeout'
}

# bats test_tags=home-manager-core
@test "vm: vm-aarch64 rbw broker tunnel waits for network-online before starting" {
  local actual

  actual=$(nix_eval_apply_raw \
    '.#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services."rbw-pinentry-touchid-broker-tunnel"' \
    'service: builtins.toJSON {
      after = service.Unit.After or [];
      wants = service.Unit.Wants or [];
      wantedBy = service.Install.WantedBy or [];
    }')

  run python - "$actual" <<'PY'
import json
import sys

(actual,) = sys.argv[1:]
payload = json.loads(actual)

after = payload.get("after", [])
wants = payload.get("wants", [])
wanted_by = payload.get("wantedBy", [])

if "network-online.target" not in after:
    print(
        f"rbw broker tunnel should start after network-online.target, got after={after!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if "network-online.target" not in wants:
    print(
        f"rbw broker tunnel should want network-online.target, got wants={wants!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if "default.target" not in wanted_by:
    print(
        f"rbw broker tunnel should still be installed into default.target, got wantedBy={wanted_by!r}",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  assert_success \
    || fail "vm-aarch64 rbw broker tunnel should wait for network-online before starting, got: $actual"

  grep -Fq 'systemd.user.services.rbw-pinentry-touchid-broker-tunnel' den/aspects/hosts/vm-aarch64.nix \
    || fail 'vm-aarch64 host aspect should own the rbw Touch ID broker tunnel service wiring'
}

# bats test_tags=home-manager-core
@test "vm: vm-aarch64 rbw-config guards the configured bridge pinentry" {
  local actual_drv

  actual_drv=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.systemd.user.services.rbw-config.serviceConfig.ExecStart \
    'execStart: builtins.head (builtins.attrNames (builtins.getContext execStart))')

  run python - "$actual_drv" <<'PY'
import json
import subprocess
import sys

(drv,) = sys.argv[1:]
payload = json.loads(
    subprocess.run(
        ["nix", "derivation", "show", drv],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
)
script_text = next(iter(payload["derivations"].values()))["env"]["text"]

required_markers = (
    'bridge_pinentry=',
    'if [ ! -x "$bridge_pinentry" ]; then',
    'rbw-config: configured pinentry',
)

for marker in required_markers:
    if marker not in script_text:
        print(
            f"rbw-config writer should explicitly guard the configured bridge pinentry with marker {marker!r}",
            file=sys.stderr,
        )
        sys.exit(1)
PY
  assert_success \
    || fail "rbw-config should explicitly guard the configured bridge pinentry helper, got derivation '$actual_drv'"

  grep -Fq 'bridge_pinentry=' den/aspects/features/secrets.nix \
    || fail 'secrets.nix should make the bridge pinentry dependency explicit in rbw-config generation'
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 has Linux pbcopy alias" {
  local zsh_aliases
  zsh_aliases=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases)
  printf '%s' "$zsh_aliases" | grep -q '"pbcopy"' \
    || fail "vm-aarch64 zsh shellAliases missing Linux 'pbcopy'; got: $zsh_aliases"
}

# bats test_tags=home-manager-core
@test "home-manager-core: vm-aarch64 has noctalia-diff-apply alias" {
  local zsh_aliases
  zsh_aliases=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.zsh.shellAliases)
  printf '%s' "$zsh_aliases" | grep -q '"noctalia-diff-apply"' \
    || fail "vm-aarch64 zsh shellAliases missing 'noctalia-diff-apply'; got: $zsh_aliases"
  printf '%s' "$zsh_aliases" | grep -Fq '/bin/noctalia-diff-apply' \
    || fail "vm-aarch64 noctalia-diff-apply alias should point at the generated helper command; got: $zsh_aliases"
  grep -Fq 'writeShellScriptBin "noctalia-diff-apply"' den/aspects/features/shell.nix \
    || fail 'shell.nix should build a dedicated noctalia-diff-apply helper'
  grep -Fq "p||/^[[:space:]]*[{]/{p=1;print}" den/aspects/features/shell.nix \
    || fail 'shell.nix should strip any non-JSON prelude before jq in the noctalia helpers'
  grep -Fq '/nixos-config/dotfiles/by-host/vm/noctalia.json' den/aspects/features/shell.nix \
    || fail 'shell.nix should keep noctalia-diff-apply writing to the tracked noctalia.json file'
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

  actual=$(nix_eval_apply_raw .#darwinConfigurations.macbook-pro-m1.config.home-manager.backupCommand 'cmd: toString cmd')
  [[ "$actual" == *home-manager-rotate-backup ]] \
    || fail "macbook-pro-m1 backupCommand unexpected: '$actual'"
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

  actual=$(nix_eval_apply_raw .#nixosConfigurations.wsl.config.home-manager.backupCommand 'cmd: toString cmd')
  [[ "$actual" == *home-manager-rotate-backup ]] \
    || fail "wsl backupCommand unexpected: '$actual'"
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
  assert_file_exists den/aspects/features/editors.nix
  assert_file_exists den/aspects/features/devtools.nix
  assert_file_exists den/aspects/features/ai-tools.nix
}

# bats test_tags=devtools
@test "devtools: editors-devtools.nix owns required packages and programs" {
  grep -Fq 'pkgs.go'                  den/aspects/features/devtools.nix
  grep -Fq 'pkgs.nodejs_22'           den/aspects/features/devtools.nix
  grep -Fq 'programs.doom-emacs'      den/aspects/features/editors.nix
  grep -Fq 'programs.tmux'            den/aspects/features/devtools.nix
  grep -Fq 'programs.vscode'          den/aspects/features/editors.nix
  grep -Fq 'programs.lazyvim'         den/aspects/features/editors.nix
  grep -Fq 'programs.go'              den/aspects/features/devtools.nix
  grep -Fq 'installWritableTmuxMenus' den/aspects/features/devtools.nix
  grep -Fq 'services.emacs'           den/aspects/features/editors.nix
  grep -Fq 'programs.starship'        den/aspects/features/devtools.nix
  grep -Fq 'programs.zellij'          den/aspects/features/devtools.nix
  grep -Fq 'pkgs.devenv'              den/aspects/features/devtools.nix
  grep -Fq 'pkgs.dust'                den/aspects/features/devtools.nix
  grep -Fq 'pkgs.zellij'              den/aspects/features/devtools.nix
}

# bats test_tags=zellij-patches
@test "zellij-patches: move-tab export carries source tab transfer plumbing" {
  local patch=patches/zellij-0004-add-move-tab-to-session-cli.patch
  grep -Fq 'diff --git a/zellij-server/src/pty.rs b/zellij-server/src/pty.rs' "$patch"
  grep -Fq 'diff --git a/zellij-server/src/session_transfer.rs b/zellij-server/src/session_transfer.rs' "$patch"
  grep -Fq 'pub source_tab_id: Option<usize>,' "$patch"
  grep -Fq '.source_tab_id' "$patch"
  grep -Fq 'CloseTabWithoutPty(' "$patch"
  grep -Fq 'source_tab_id: None,' "$patch"
  grep -Fq 'source_tab_id,' "$patch"
}

# bats test_tags=zellij-patches
@test "zellij-patches: macOS session transfer socket hardening is shipped as a follow-up patch" {
  local patch=patches/zellij-0005-harden-macos-session-transfer-sockets.patch
  assert_file_exists "$patch"
  grep -Fq 'zellij-0005-harden-macos-session-transfer-sockets.patch' den/mk-config-outputs.nix
  grep -Fq 'ZELLIJ_TMP_DIR' "$patch"
  grep -Fq '.join("session-transfer")' "$patch"
  grep -Fq 'Failed to rename session transfer socket' "$patch"
  grep -Fq 'session_transfer_socket_path_fits_macos_socket_limit' "$patch"
  grep -Fq 'renaming_session_immediately_after_startup_moves_transfer_listener_socket' "$patch"
}

# bats test_tags=devtools
@test "devtools: ai-tools.nix owns AI package and program entries" {
  grep -Fq 'pkgs.claude-code-acp'                    den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.copilot-cli'             den/aspects/features/ai-tools.nix
  grep -Fq 'programs.opencode'                        den/aspects/features/ai-tools.nix
  grep -Fq 'package = pkgs.opencode;'                 den/aspects/features/ai-tools.nix
  grep -Fq 'agent-shell-copilot-acp'                 den/aspects/features/ai-tools.nix
  grep -Fq 'agent-shell-claude-code-acp'             den/aspects/features/ai-tools.nix
  grep -Fq 'agent-shell-opencode-acp'                den/aspects/features/ai-tools.nix
  grep -Fq 'opencode-auth-refresh'                   den/aspects/features/ai-tools.nix
  grep -Fq '.local/share/opencode'                   den/aspects/features/ai-tools.nix
  grep -Fq 'opencode-auth-bailian-coding-plan'       den/aspects/features/ai-tools.nix
  grep -Fq 'opencode-auth-github-copilot'            den/aspects/features/ai-tools.nix
  grep -Fq 'opencode-auth-opencode-go'               den/aspects/features/ai-tools.nix
  grep -Fq 'export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH' den/aspects/features/ai-tools.nix
  grep -Fq 'bailian-coding-plan'                     den/aspects/features/ai-tools.nix
  grep -Fq 'github-copilot'                          den/aspects/features/ai-tools.nix
  grep -Fq 'opencode-go'                             den/aspects/features/ai-tools.nix
  if grep -Fq 'cp "$authJson" "$tmpJson"' den/aspects/features/ai-tools.nix; then
    fail 'opencode auth generation must overwrite from rbw, not merge existing auth.json'
  fi
  grep -Fq 'rbw stop-agent || true'                  den/aspects/features/ai-tools.nix
  grep -Fq 'export XDG_CONFIG_HOME="$HOME/.config"' den/aspects/features/ai-tools.nix
  grep -Fq 'opencodeAwesome'                          den/aspects/features/ai-tools.nix
  grep -Fq 'ensureOpencodePackageJsonWritable'        den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.dotagents'                           den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.apm'                                 den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.beads'                    den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.openspec'                 den/aspects/features/ai-tools.nix
  grep -Fq 'pkgs.llm-agents.copilot-language-server'  den/aspects/features/ai-tools.nix
  grep -Fq 'ocd = "opencode";'                        den/aspects/features/shell.nix
  if grep -Fq 'opencode/modules/home-manager.nix' den/aspects/features/ai-tools.nix; then
    fail 'ai-tools.nix must not import opencode/modules/home-manager.nix (deleted)'
  fi
  if rg -n 'pkgs\.llm-agents\.opencode|pkgs\.opencode-dev|opencode-dev' \
    den/aspects/features/ai-tools.nix \
    den/aspects/features/shell.nix \
    den/aspects/hosts/vm-aarch64.nix \
    dotfiles/common/opencode/modules/darwin.nix \
    den/mk-config-outputs.nix \
    >/dev/null; then
    fail 'OpenCode must use a single upstream package; stale llm-agents/opencode-dev references remain'
  fi
  grep -Fq 'opencode-serve' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'opencode-web'   den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=devtools
@test "devtools: ai-tools.nix does not fetch opencode auth during home-manager activation" {
  grep -Fq 'opencode-auth-refresh' den/aspects/features/ai-tools.nix

  if grep -Fq 'home.activation.ensureOpencodeAuthJson' den/aspects/features/ai-tools.nix; then
    fail 'opencode auth refresh must not run during Home Manager activation'
  fi
}

# bats test_tags=devtools
@test "devtools: doom config wires agent-shell ACP commands" {
  grep -Fq 'exec-path-from-shell-initialize'                            dotfiles/common/doom/config.el
  grep -Fq 'agent-shell-copilot-acp'                                    dotfiles/common/doom/config.el
  grep -Fq 'agent-shell-claude-code-acp'                                dotfiles/common/doom/config.el
  grep -Fq 'agent-shell-opencode-acp'                                   dotfiles/common/doom/config.el
  grep -Fq 'agent-shell-opencode-make-authentication :none t'           dotfiles/common/doom/config.el
}

# bats test_tags=devtools
@test "devtools: user m aspect wires editors-devtools and ai-tools" {
  grep -Fq 'den.aspects.editors'  den/aspects/users/m.nix
  grep -Fq 'den.aspects.devtools' den/aspects/users/m.nix
  grep -Fq 'den.aspects.ai-tools'         den/aspects/users/m.nix
}

# bats test_tags=devtools
@test "devtools: Task 6 aspects do not contain out-of-scope items" {
  for aspect in den/aspects/features/editors.nix den/aspects/features/devtools.nix den/aspects/features/ai-tools.nix; do
    local non_comment
    non_comment=$(grep -Ev '^[[:space:]]*#' "$aspect")
    if printf '%s\n' "$non_comment" | grep -Eq 'load_plugins'; then
      fail "$aspect contains load_plugins — must stay in host aspects"
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
  printf '%s' "$mac_packages" | grep -q 'claude-code-acp' \
    || fail "macbook-pro-m1 home.packages missing claude-code-acp"
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

# bats test_tags=linux-core
@test "linux: vm-aarch64 sudo uses macOS touchid bridge" {
  local actual

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.security.pam.services.sudo.text)

  run python - "$actual" <<'PY'
import sys

actual = sys.argv[1]
lines = actual.splitlines()

bridge_index = next(
    (
        idx
        for idx, line in enumerate(lines)
        if line.startswith("auth ")
        and "pam_exec.so" in line
        and "sufficient" in line
    ),
    None,
)
fallback_index = next(
    (
        idx
        for idx, line in enumerate(lines)
        if line.startswith("auth ")
        and "pam_unix.so likeauth try_first_pass" in line
        and "sufficient" in line
    ),
    None,
)

if bridge_index is None:
    print(
        "vm-aarch64 sudo PAM should include an auth-sufficient pam_exec bridge line",
        file=sys.stderr,
    )
    sys.exit(1)

if fallback_index is None:
    print(
        "vm-aarch64 sudo PAM lost the auth-sufficient pam_unix.so likeauth try_first_pass fallback line",
        file=sys.stderr,
    )
    sys.exit(1)

if bridge_index >= fallback_index:
    print(
        "vm-aarch64 sudo PAM should place the auth bridge line before the pam_unix fallback line",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  assert_success || fail "vm-aarch64 sudo PAM bridge ordering is wrong, got: $actual"
}

# bats test_tags=linux-core
@test "linux: vm-aarch64 sudo touchid bridge runs pam_exec with seteuid" {
  local actual

  actual=$(nix_eval_apply_raw \
    '.#nixosConfigurations.vm-aarch64.config.security.pam.services.sudo.rules.auth."vm-touchid-bridge".args' \
    'args: builtins.concatStringsSep "\n" args')

  printf '%s\n' "$actual" | grep -Fxq 'seteuid' \
    || fail "vm-aarch64 sudo PAM bridge should include seteuid, got: $actual"
}


# bats test_tags=linux-core
@test "linux: vm-aarch64 sudo touchid bridge uses a root-trusted broker tunnel" {
  local actual bridge_path bridge_drv tunnel_path tunnel_drv

  actual=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.systemd.services \
    'services: if services ? "vm-touchid-sudo-broker-tunnel" then "yes" else "no"')
  assert_equal "$actual" "yes"

  bridge_path=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.environment.systemPackages \
    'pkgs:
      let
        matches = builtins.filter (pkg: builtins.match ".*vm-touchid-sudo-bridge.*" (toString pkg) != null) pkgs;
      in
      toString (builtins.head matches)')
  [[ "$bridge_path" == /nix/store/* ]] \
    || fail "vm-touchid-sudo-bridge should evaluate to a store-backed helper path, got '$bridge_path'"

  bridge_drv=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.environment.systemPackages \
    'pkgs:
      let
        matches = builtins.filter (pkg: builtins.match ".*vm-touchid-sudo-bridge.*" (toString pkg) != null) pkgs;
      in
      builtins.head (builtins.attrNames (builtins.getContext (toString (builtins.head matches))))')

  tunnel_path=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.systemd.services.vm-touchid-sudo-broker-tunnel.serviceConfig.ExecStart)
  [[ "$tunnel_path" == /nix/store/*/bin/* ]] \
    || fail "vm-touchid-sudo-broker-tunnel should evaluate to a store-backed helper path, got '$tunnel_path'"

  tunnel_drv=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.systemd.services.vm-touchid-sudo-broker-tunnel.serviceConfig.ExecStart \
    'execStart: builtins.head (builtins.attrNames (builtins.getContext execStart))')

  run python - "$bridge_drv" "$tunnel_drv" <<'PY'
import json
import subprocess
import sys

bridge_drv, tunnel_drv = sys.argv[1:3]

def derivation_text(drv: str) -> str:
    payload = json.loads(
        subprocess.run(
            ["nix", "derivation", "show", drv],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    return next(iter(payload["derivations"].values()))["env"]["text"]

bridge_text = derivation_text(bridge_drv)
tunnel_text = derivation_text(tunnel_drv)
expected_socket = "/run/vm-touchid-sudo-broker.sock"
legacy_socket = "/home/m/.local/run/vm-touchid-broker.sock"

if f'BROKER_SOCKET = "{expected_socket}"' not in bridge_text:
    print(
        f"sudo bridge does not point at the root-trusted broker socket {expected_socket!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if legacy_socket in bridge_text:
    print(
        f"sudo bridge still references the legacy user-controlled broker socket {legacy_socket!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if expected_socket not in tunnel_text:
    print(
        f"sudo broker tunnel does not expose the expected root runtime socket {expected_socket!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if "ssh -N" not in tunnel_text or "/Users/m/Library/Caches/vm-touchid-broker.sock" not in tunnel_text:
    print(
        "sudo broker tunnel derivation no longer encodes an SSH tunnel to the macOS Touch ID broker socket",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  assert_success \
    || fail "vm-aarch64 sudo should trust a root-owned tunnel endpoint instead of the legacy user-home broker socket"
}

# bats test_tags=linux-core,home-manager-core
@test "linux: vm-aarch64 touchid bridge ssh hardening is fail-closed" {
  local user_tunnel_drv sudo_tunnel_drv

  user_tunnel_drv=$(nix_eval_apply_raw \
    '.#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services."rbw-pinentry-touchid-broker-tunnel".Service.ExecStart' \
    'execStart:
      let
        command = builtins.elemAt execStart 0;
      in
      builtins.head (builtins.attrNames (builtins.getContext command))')

  sudo_tunnel_drv=$(nix_eval_apply_raw \
    '.#nixosConfigurations.vm-aarch64.config.systemd.services.vm-touchid-sudo-broker-tunnel.serviceConfig.ExecStart' \
    'execStart: builtins.head (builtins.attrNames (builtins.getContext execStart))')

  run python - "$user_tunnel_drv" "$sudo_tunnel_drv" <<'PY'
import json
import re
import shlex
import subprocess
import sys

user_tunnel_drv, sudo_tunnel_drv = sys.argv[1:3]

COMMON_REQUIRED = (
    "-F /dev/null",
    "-o BatchMode=yes",
    "-o IdentitiesOnly=yes",
    "-o GlobalKnownHostsFile=/dev/null",
    "-o StrictHostKeyChecking=yes",
)
COMMON_FORBIDDEN = (
    "ssh-keygen -R",
    "StrictHostKeyChecking=accept-new",
)
ROLE_SPECIFIC = {
    "rbw": (
        "~/.ssh/id_ed25519_touchid_bridge_to_host",
        "$HOME/.ssh/id_ed25519_touchid_bridge_to_host",
        "${HOME}/.ssh/id_ed25519_touchid_bridge_to_host",
        "/home/m/.ssh/id_ed25519_touchid_bridge_to_host",
    ),
    "sudo": (
        "/var/lib/vm-touchid-sudo-bridge/id_ed25519",
    ),
}


def derivation_text(drv: str) -> str:
    payload = json.loads(
        subprocess.run(
            ["nix", "derivation", "show", drv],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    return next(iter(payload["derivations"].values()))["env"]["text"]


def logical_commands(text: str) -> list[str]:
    commands: list[str] = []
    current: list[str] = []

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            if current:
                commands.append(" ".join(current))
                current = []
            continue

        current.append(stripped.removesuffix("\\").strip())
        if not stripped.endswith("\\"):
            commands.append(" ".join(current))
            current = []

    if current:
        commands.append(" ".join(current))

    return commands


def extract_bridge_ssh_commands(text: str) -> list[str]:
    return [
        command
        for command in logical_commands(text)
        if re.search(r"(^|\s)(?:\S*/)?ssh(\s|$)", command)
    ]


def normalize_option_value(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def extract_option_values(text: str, option_name: str) -> list[str]:
    values: list[str] = []
    tokens = shlex.split(text, posix=True)
    index = 0

    while index < len(tokens):
        token = tokens[index]

        if token == "-o" and index + 1 < len(tokens):
            payload = tokens[index + 1]
            if payload.startswith(f"{option_name}="):
                values.append(payload.split("=", 1)[1])
                index += 2
                continue
            if payload.startswith(f"{option_name} "):
                values.append(payload.split(None, 1)[1])
                index += 2
                continue
            if payload == option_name and index + 2 < len(tokens):
                values.append(tokens[index + 2])
                index += 3
                continue
        elif token.startswith(f"-o{option_name}="):
            values.append(token.split("=", 1)[1])
        elif token == f"-o{option_name}" and index + 1 < len(tokens):
            values.append(tokens[index + 1])
            index += 2
            continue

        index += 1

    return values


def extract_identity_values(text: str) -> list[str]:
    return extract_option_values(text, "IdentityFile")


def normalized_identity_values(text: str) -> list[str]:
    return [normalize_option_value(value) for value in extract_identity_values(text)]


def has_identity_option(text: str, identities: tuple[str, ...] | str) -> bool:
    candidates = {identities} if isinstance(identities, str) else set(identities)
    return any(value in candidates for value in normalized_identity_values(text))


def unexpected_identity_values(text: str, identities: tuple[str, ...] | str) -> list[str]:
    candidates = {identities} if isinstance(identities, str) else set(identities)
    return sorted({value for value in normalized_identity_values(text) if value not in candidates})


def has_generic_identity_flag(text: str) -> bool:
    tokens = shlex.split(text, posix=True)
    for index, token in enumerate(tokens):
        if token == "-i" and index + 1 < len(tokens):
            return True
        if token.startswith("-i") and token != "-i":
            return True
    return False


def extract_user_known_hosts_values(text: str) -> list[str]:
    return extract_option_values(text, "UserKnownHostsFile")


def has_dedicated_user_known_hosts_option(text: str, allowed_pattern: str) -> bool:
    defaults = {
        "/dev/null",
        "/home/m/.ssh/known_hosts",
        "/Users/m/.ssh/known_hosts",
        "~/.ssh/known_hosts",
        "$HOME/.ssh/known_hosts",
        "${HOME}/.ssh/known_hosts",
    }
    values = extract_user_known_hosts_values(text)
    if not values:
        return False
    effective_value = normalize_option_value(values[-1])
    return effective_value not in defaults and re.search(allowed_pattern, effective_value) is not None


def validate_tunnel(name: str, text: str) -> list[str]:
    failures: list[str] = []
    ssh_commands = extract_bridge_ssh_commands(text)

    for forbidden in COMMON_FORBIDDEN:
        if forbidden in text:
            failures.append(f"{name} tunnel still contains forbidden {forbidden!r}")

    if not ssh_commands:
        failures.append(f"could not find any bridge ssh invocations in the {name} tunnel")

    for command in ssh_commands:
        for required in COMMON_REQUIRED:
            if required not in command:
                failures.append(f"{name} tunnel is missing required {required!r}: {command}")

        if has_generic_identity_flag(command):
            failures.append(
                f"{name} tunnel should not use generic ssh -i identity flags when the contract requires explicit IdentityFile options: {command}"
            )

        expected_identity = ROLE_SPECIFIC[name]
        if not has_identity_option(command, expected_identity):
            failures.append(
                f"{name} tunnel should use a dedicated bridge IdentityFile SSH option for {expected_identity[0]!r}"
            )

        unexpected_identities = unexpected_identity_values(command, expected_identity)
        if unexpected_identities:
            failures.append(
                f"{name} tunnel should not configure additional IdentityFile SSH options beyond the dedicated bridge key: {unexpected_identities!r}"
            )

        if name == "rbw" and not has_dedicated_user_known_hosts_option(
            command,
            r"^(?:~|\$HOME|\$\{HOME\}|/home/m)/\.ssh/\S*known_hosts\S*$",
        ):
            failures.append(
                f"{name} tunnel should point UserKnownHostsFile at a dedicated pinned bridge known_hosts file under the user SSH directory"
            )

        if name == "sudo" and not has_dedicated_user_known_hosts_option(
            command,
            r"^/var/lib/vm-touchid-sudo-bridge/\S*known_hosts\S*$",
        ):
            failures.append(
                f"{name} tunnel should point UserKnownHostsFile at a dedicated pinned root-owned known_hosts file under /var/lib/vm-touchid-sudo-bridge"
            )

    return failures


failures = []
for tunnel_name, tunnel_drv in (("rbw", user_tunnel_drv), ("sudo", sudo_tunnel_drv)):
    failures.extend(validate_tunnel(tunnel_name, derivation_text(tunnel_drv)))

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY
  assert_success \
    || fail "vm-aarch64 touchid bridge tunnels should fail closed with dedicated bridge SSH trust"
}

# bats test_tags=linux-core
@test "linux: vm-aarch64 sudo broker tunnel waits for network-online before starting" {
  local actual

  actual=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.systemd.services.vm-touchid-sudo-broker-tunnel \
    'service: builtins.toJSON {
      after = service.after or [];
      wants = service.wants or [];
      wantedBy = service.wantedBy or [];
    }')

  run python - "$actual" <<'PY'
import json
import sys

(actual,) = sys.argv[1:]
payload = json.loads(actual)

after = payload.get("after", [])
wants = payload.get("wants", [])
wanted_by = payload.get("wantedBy", [])

if "network-online.target" not in after:
    print(
        f"sudo broker tunnel should start after network-online.target, got after={after!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if "network-online.target" not in wants:
    print(
        f"sudo broker tunnel should want network-online.target, got wants={wants!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if "multi-user.target" not in wanted_by:
    print(
        f"sudo broker tunnel should still be installed into multi-user.target, got wantedBy={wanted_by!r}",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  assert_success \
    || fail "vm-aarch64 sudo broker tunnel should wait for network-online before starting, got: $actual"

  grep -Fq 'systemd.services.vm-touchid-sudo-broker-tunnel' den/aspects/hosts/vm-aarch64.nix \
    || fail 'vm-aarch64 host aspect should own the sudo Touch ID broker tunnel service wiring'
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
@test "vm-desktop: vmware.nix keeps only generic VMware guest settings" {
  grep -Fq 'virtualisation.vmware.guest.enable = true;' den/aspects/features/vmware.nix
  grep -Fq 'environment.systemPackages = [ pkgs.gtkmm3 ];' den/aspects/features/vmware.nix

  if grep -Eq 'programs\.ssh|programs\.niri\.settings|DOCKER_CONTEXT|yeetAndYoink|mac-host-docker|ensureHostDockerContext|uniclip|\.host:/Projects|\.host:/nixos-config|\.host:/nixos-generated|allowUnsupportedSystem|allowUnfree' den/aspects/features/vmware.nix; then
    fail 'den/aspects/features/vmware.nix should keep only generic VMware guest settings'
  fi
}

# bats test_tags=vm-desktop
@test "vm-desktop: vmware.nix no longer checks host.vmware.enable" {
  if grep -Eq 'host\.vmware\.enable|isVM' den/aspects/features/vmware.nix; then
    fail 'den/aspects/features/vmware.nix should not check host.vmware.enable'
  fi
}

# bats test_tags=vm-desktop
@test "vm-desktop: scripts and docs reference external-input-flake.sh correctly" {
  grep -Fq 'external-input-flake.sh' docs/vm.sh
  grep -Fq 'external-input-flake.sh' den/aspects/features/shell.nix
  if grep -Fq 'git+file://$yeet_dir?dir=plugins/zellij-break' scripts/external-input-flake.sh; then
    fail 'scripts/external-input-flake.sh must not contain yeetnyoink git+file wrapper'
  fi
  if grep -Fq 'YEET_AND_YOINK_INPUT_DIR' den/aspects/features/shell.nix; then
    fail 'shell.nix must not reference YEET_AND_YOINK_INPUT_DIR'
  fi
  if grep -Fq 'YEET_AND_YOINK_INPUT_DIR' docs/vm.sh; then
    fail 'docs/vm.sh must not reference YEET_AND_YOINK_INPUT_DIR'
  fi
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
@test "vm-desktop: vm-aarch64 owns VMware bridge config" {
  grep -Fq 'nixpkgs.config.allowUnfree = true;' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'nixpkgs.config.allowUnsupportedSystem = true;' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '.host:/Projects' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '.host:/nixos-config' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '.host:/nixos-generated' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'inputs.yeetnyoink.homeManagerModules.default' den/aspects/features/linux-desktop.nix
  grep -Fq 'pkgs.yeetnyoink' den/aspects/features/linux-desktop.nix
  grep -Fq 'programs.ssh' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'programs.niri.settings' den/aspects/features/linux-desktop.nix
  grep -Fq 'DOCKER_CONTEXT' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'ensureHostDockerContext' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'mac-host-docker' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'systemd.user.services.uniclip' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'pkgs.docker-client' den/aspects/hosts/vm-aarch64.nix
  if grep -Fq 'yeetAndYoink.requirePath' den/aspects/hosts/vm-aarch64.nix; then
    fail 'vm-aarch64.nix still uses yeetAndYoink.requirePath — replace with pkgs.yeetnyoink'
  fi
  if grep -Fq 'load_plugins' den/aspects/hosts/vm-aarch64.nix; then
    fail 'vm-aarch64.nix still configures load_plugins (Zellij plugin removed)'
  fi
}

# bats test_tags=vm-desktop
@test "vm-desktop: vm-aarch64 self-heals git fileMode for shared repos" {
  grep -Fq 'repairSharedGitFileMode = pkgs.writeShellScriptBin "repair-shared-git-filemode"' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'repairingGit = pkgs.writeShellScriptBin "git"' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'programs.git.package = repairingGit;' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'root=$("$git_bin" -C "$workdir" rev-parse --show-toplevel 2>/dev/null)' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '"$repair_bin" "$root"' den/aspects/hosts/vm-aarch64.nix
  grep -Fq -- '--work-tree' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'systemd.user.services."repair-shared-git-filemode"' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'ExecStart = "${repairSharedGitFileMode}/bin/repair-shared-git-filemode";' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'home.activation.ensureSharedGitFileMode' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '/nixos-config|/Users/m/Projects|/Users/m/Projects/*' den/aspects/hosts/vm-aarch64.nix

  if grep -Fq '"$find_bin"' den/aspects/hosts/vm-aarch64.nix; then
    fail 'vm-aarch64.nix should not scan /Users/m/Projects during activation-time repair'
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
@test "vm-desktop: vm-aarch64 greetd exposes hyprland and i3 sessions" {
  local actual

  actual=$(nix_eval_json .#nixosConfigurations.vm-aarch64.config.services.displayManager.sessionPackages)
  printf '%s' "$actual" | grep -q 'hyprland' \
    || fail "sessionPackages missing hyprland; got '$actual'"
  printf '%s' "$actual" | grep -q 'i3' \
    || fail "sessionPackages missing i3; got '$actual'"

  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.services.greetd.settings.default_session.command)
  printf '%s' "$actual" | grep -q -- '--xsessions' \
    || fail "greetd command missing --xsessions; got '$actual'"
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
# kube-passthrough — hardened OrbStack access from the VM
# ===========================================================================

# bats test_tags=kube-passthrough
@test "kube-passthrough: macOS syncs kubeconfig from Bitwarden into the generated dataset" {
  grep -Fq 'launchd.user.agents.orbstack-kubeconfig-sync' den/aspects/features/darwin-core.nix
  grep -Fq 'kubeconfigBitwardenItem = "orbstack-kubeconfig";' den/aspects/features/darwin-core.nix
  grep -Fq 'rbw get ${kubeconfigBitwardenItem}' den/aspects/features/darwin-core.nix
  grep -Fq 'StartInterval = 300;' den/aspects/features/darwin-core.nix
  grep -Fq 'refresh-kubeconfig' docs/vm.sh
  grep -Fq 'RBW_BIN' docs/vm.sh
  grep -Fq 'orbstack-kubeconfig' docs/secrets.md
  grep -Fq 'rbw add orbstack-kubeconfig' docs/secrets.md
  if grep -Fq 'WatchPaths' den/aspects/features/darwin-core.nix; then
    fail 'macOS kubeconfig sync should poll Bitwarden instead of watching ~/.kube/config'
  fi
  if grep -Fq '/Users/m/.kube/config' den/aspects/features/darwin-core.nix; then
    fail 'macOS kubeconfig sync should not read from the local kubeconfig file'
  fi
}

# bats test_tags=kube-passthrough
@test "kube-passthrough: vm broker rewrites kubeconfig and removes the fixed 26443 tunnel" {
  grep -Fq 'systemd.user.services.kubectl-passthrough' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'config set-cluster' den/aspects/hosts/vm-aarch64.nix
  grep -Fq '127.0.0.1' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'config view --raw -o jsonpath' den/aspects/hosts/vm-aarch64.nix
  if grep -Fq 'kubectl-orbstack-tunnel' den/aspects/hosts/vm-aarch64.nix; then
    fail 'vm-aarch64 should not keep the fixed kubectl-orbstack-tunnel service'
  fi
  if grep -Fq -- '-L 26443:localhost:26443' den/aspects/hosts/vm-aarch64.nix; then
    fail 'vm-aarch64 should not hardcode a single 26443 tunnel'
  fi
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
@test "darwin: macbook-pro-m1 homebrew casks include macfuse for s3fs" {
  local casks

  casks=$(nix_eval_json .#darwinConfigurations.macbook-pro-m1.config.homebrew.casks)
  printf '%s' "$casks" | grep -Fq '"macfuse"' \
    || fail "macbook-pro-m1 homebrew.casks missing macfuse required by s3fs on Darwin"
}

# bats test_tags=darwin
@test "darwin: git aspect wires rbw Touch ID adapter activation" {
  local actual

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.activation \
    'activation: builtins.concatStringsSep "," (builtins.attrNames activation)')
  [[ ",$actual," == *",ensureDarwinRbwPinentry,"* ]] \
    || fail "macbook-pro-m1 home.activation missing ensureDarwinRbwPinentry; got: $actual"

  actual=$(nix_eval_apply_raw \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.home.activation \
    'activation: builtins.concatStringsSep "," (builtins.attrNames activation)')
  [[ ",$actual," != *",ensureDarwinRbwPinentry,"* ]] \
    || fail "vm-aarch64 unexpectedly includes Darwin rbw pinentry activation; got: $actual"

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.home-manager.users.m.home.activation.ensureDarwinRbwPinentry \
    'activation: activation.data')
  [[ "$actual" == *"rbw-pinentry-touchid"* ]] \
    || fail "Darwin rbw activation should set pinentry to the adapter wrapper; got: $actual"

  grep -Fq 'OPTION allow-external-password-cache' den/aspects/features/git.nix \
    || fail 'git aspect missing allow-external-password-cache adapter shim'
  grep -Fq 'SETKEYINFO {keyinfo}' den/aspects/features/git.nix \
    || fail 'git aspect missing SETKEYINFO adapter shim'
  grep -Fq 'Bitwarden RBW <{email}>' den/aspects/features/git.nix \
    || fail 'git aspect missing stable Bitwarden RBW keychain label'
  grep -Fq 'if raw == "GETPIN\n":' den/aspects/features/git.nix \
    || fail 'git aspect missing newline-terminated GETPIN adapter handling'
  grep -Fq 'send_and_forward(desc + "\n")' den/aspects/features/git.nix \
    || fail 'git aspect missing newline-terminated SETDESC forwarding'
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

# bats test_tags=darwin
@test "darwin: evaluated macOS touchid broker agent is wired" {
  local actual

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents \
    'agents: if agents ? "rbw-pinentry-touchid-broker" then "yes" else "no"')
  assert_equal "$actual" "yes"

  actual=$(nix_eval_apply_raw \
    .#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents."rbw-pinentry-touchid-broker".serviceConfig.ProgramArguments \
    'args: builtins.concatStringsSep "\n" args')
  [[ "$actual" == *pinentry-touchid* ]] \
    || fail 'Darwin touchid broker agent should launch a payload that references pinentry-touchid'
}

# bats test_tags=darwin
@test "darwin: macOS touchid broker waits for the interactive Aqua session" {
  local actual

  actual=$(nix_eval_apply_raw \
    '.#darwinConfigurations.macbook-pro-m1.config.launchd.user.agents."rbw-pinentry-touchid-broker"' \
    'agent: builtins.toJSON {
      limitLoadToSessionType = agent.serviceConfig.LimitLoadToSessionType or null;
      processType = agent.serviceConfig.ProcessType or null;
    }')

  run python - "$actual" <<'PY'
import json
import sys

(actual,) = sys.argv[1:]
payload = json.loads(actual)

if payload.get("limitLoadToSessionType") != "Aqua":
    print(
        f"Touch ID broker should be limited to the Aqua session, got {payload.get('limitLoadToSessionType')!r}",
        file=sys.stderr,
    )
    sys.exit(1)

if payload.get("processType") != "Interactive":
    print(
        f"Touch ID broker should be marked interactive for GUI readiness, got {payload.get('processType')!r}",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  assert_success \
    || fail "Darwin touchid broker should wait for the interactive Aqua session, got: $actual"

  grep -Fq 'launchd.user.agents.rbw-pinentry-touchid-broker' den/aspects/features/darwin-core.nix \
    || fail 'darwin-core.nix should own the macOS Touch ID broker agent wiring'
}

# bats test_tags=darwin
@test "darwin: macOS touchid bridge reverse tunnel hardening is fail-closed" {
  run python - <<'PY'
from pathlib import Path
import re
import shlex
import sys

text = Path("den/aspects/features/darwin-core.nix").read_text()


def extract_nix_attr_block(text: str, marker: str) -> str:
    start = text.index(marker)
    block_lines: list[str] = []
    brace_depth = 0
    in_multiline_string = False

    for line in text[start:].splitlines():
        block_lines.append(line)

        if not in_multiline_string:
            brace_depth += line.count("{") - line.count("}")
            if brace_depth == 0:
                return "\n".join(block_lines)

        if line.count("''") % 2 == 1:
            in_multiline_string = not in_multiline_string

    raise ValueError(f"could not extract attr block for {marker!r}")


agent_block = extract_nix_attr_block(text, 'launchd.user.agents.vm-touchid-broker-tunnel = {')


def extract_reverse_tunnel(text: str) -> str:
    for command in extract_bridge_ssh_commands(text):
        if re.search(r"(^|\s)-R(\s|$)", command):
            return command
    raise ValueError("could not find the reverse-tunnel ssh invocation")


def logical_commands(text: str) -> list[str]:
    commands: list[str] = []
    current: list[str] = []

    for raw_line in text.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            if current:
                commands.append(" ".join(current))
                current = []
            continue

        current.append(stripped.removesuffix("\\").strip())
        if not stripped.endswith("\\"):
            commands.append(" ".join(current))
            current = []

    if current:
        commands.append(" ".join(current))

    return commands


def extract_bridge_ssh_commands(text: str) -> list[str]:
    return [
        command
        for command in logical_commands(text)
        if re.search(r"(^|\s)(?:\S*/)?ssh(\s|$)", command)
    ]


reverse_tunnel = extract_reverse_tunnel(agent_block)
ssh_commands = extract_bridge_ssh_commands(agent_block)

required = (
    "-F /dev/null",
    "-o BatchMode=yes",
    "-o IdentitiesOnly=yes",
    "-o GlobalKnownHostsFile=/dev/null",
    "-o StrictHostKeyChecking=yes",
    "-R ${vmTouchIdRemoteSocket}:${vmTouchIdBrokerSocket}",
)
forbidden = (
    "ssh-keygen -R",
    "StrictHostKeyChecking=accept-new",
)


def normalize_option_value(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def extract_option_values(text: str, option_name: str) -> list[str]:
    values: list[str] = []
    tokens = shlex.split(text, posix=True)
    index = 0

    while index < len(tokens):
        token = tokens[index]

        if token == "-o" and index + 1 < len(tokens):
            payload = tokens[index + 1]
            if payload.startswith(f"{option_name}="):
                values.append(payload.split("=", 1)[1])
                index += 2
                continue
            if payload.startswith(f"{option_name} "):
                values.append(payload.split(None, 1)[1])
                index += 2
                continue
            if payload == option_name and index + 2 < len(tokens):
                values.append(tokens[index + 2])
                index += 3
                continue
        elif token.startswith(f"-o{option_name}="):
            values.append(token.split("=", 1)[1])
        elif token == f"-o{option_name}" and index + 1 < len(tokens):
            values.append(tokens[index + 1])
            index += 2
            continue

        index += 1

    return values


def extract_identity_values(text: str) -> list[str]:
    return extract_option_values(text, "IdentityFile")


def normalized_identity_values(text: str) -> list[str]:
    return [normalize_option_value(value) for value in extract_identity_values(text)]


def has_identity_option(text: str, identities: tuple[str, ...] | str) -> bool:
    candidates = {identities} if isinstance(identities, str) else set(identities)
    return any(value in candidates for value in normalized_identity_values(text))


def unexpected_identity_values(text: str, identities: tuple[str, ...] | str) -> list[str]:
    candidates = {identities} if isinstance(identities, str) else set(identities)
    return sorted({value for value in normalized_identity_values(text) if value not in candidates})


def has_generic_identity_flag(text: str) -> bool:
    tokens = shlex.split(text, posix=True)
    for index, token in enumerate(tokens):
        if token == "-i" and index + 1 < len(tokens):
            return True
        if token.startswith("-i") and token != "-i":
            return True
    return False


def extract_user_known_hosts_values(text: str) -> list[str]:
    return extract_option_values(text, "UserKnownHostsFile")


def has_dedicated_user_known_hosts_option(text: str) -> bool:
    defaults = {
        "/dev/null",
        "/home/m/.ssh/known_hosts",
        "/Users/m/.ssh/known_hosts",
        "~/.ssh/known_hosts",
        "$HOME/.ssh/known_hosts",
        "${HOME}/.ssh/known_hosts",
    }
    values = extract_user_known_hosts_values(text)
    if not values:
        return False
    effective_value = normalize_option_value(values[-1])
    return (
        effective_value not in defaults
        and re.search(
            r"^(?:~|\$HOME|\$\{HOME\}|/Users/m)/\.ssh/\S*known_hosts\S*$",
            effective_value,
        )
        is not None
    )

failures = []
if not ssh_commands:
    failures.append("could not find any bridge ssh invocations in the Darwin tunnel agent")

for command in ssh_commands:
    for needle in required[:-1]:
        if needle not in command:
            failures.append(f"bridge ssh command is missing required {needle!r}: {command}")

    if has_generic_identity_flag(command):
        failures.append(
            f"bridge ssh commands should not use generic ssh -i identity flags when the contract requires explicit IdentityFile options: {command}"
        )

    if not has_identity_option(
        command,
        (
            "~/.ssh/id_ed25519_touchid_bridge_to_vm",
            "$HOME/.ssh/id_ed25519_touchid_bridge_to_vm",
            "${HOME}/.ssh/id_ed25519_touchid_bridge_to_vm",
            "/Users/m/.ssh/id_ed25519_touchid_bridge_to_vm",
        ),
    ):
        failures.append(
            "bridge ssh commands should use a dedicated bridge IdentityFile SSH option for '~/.ssh/id_ed25519_touchid_bridge_to_vm'"
        )

    unexpected_identities = unexpected_identity_values(
        command,
        (
            "~/.ssh/id_ed25519_touchid_bridge_to_vm",
            "$HOME/.ssh/id_ed25519_touchid_bridge_to_vm",
            "${HOME}/.ssh/id_ed25519_touchid_bridge_to_vm",
            "/Users/m/.ssh/id_ed25519_touchid_bridge_to_vm",
        ),
    )
    if unexpected_identities:
        failures.append(
            f"bridge ssh commands should not configure additional IdentityFile SSH options beyond the dedicated bridge key: {unexpected_identities!r}"
        )

    if not has_dedicated_user_known_hosts_option(command):
        failures.append(
            "bridge ssh commands should point UserKnownHostsFile at a dedicated pinned bridge known_hosts file"
        )

if not re.search(r"(^|\s)(?:\S*/)?ssh(\s|$)", reverse_tunnel) or " -R " not in reverse_tunnel or not re.search(r"(^|\s)-N(\s|$)", reverse_tunnel):
    failures.append("could not isolate the actual ssh -N ... -R reverse-tunnel invocation")

for needle in required:
    if needle not in reverse_tunnel:
        failures.append(f"reverse tunnel is missing required {needle!r}")

for needle in forbidden:
    if needle in reverse_tunnel:
        failures.append(f"reverse tunnel still contains forbidden {needle!r}")

if "ssh-keygen -R" in agent_block:
    failures.append("reverse-tunnel implementation should not mutate known_hosts with 'ssh-keygen -R'")

if "StrictHostKeyChecking=accept-new" in agent_block and "StrictHostKeyChecking=accept-new" not in reverse_tunnel:
    failures.append("reverse-tunnel implementation should not re-TOFU with 'StrictHostKeyChecking=accept-new'")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY
  assert_success \
    || fail "darwin reverse touchid bridge tunnel should pin dedicated bridge SSH trust instead of re-TOFU"
}

# bats test_tags=darwin,home-manager-core,linux-core
@test "touchid bridge local ssh identities are created with dedicated paths" {
  run python - <<'PY'
from pathlib import Path
import re
import sys


def extract_nix_attr_block(text: str, marker: str) -> str | None:
    try:
        start = text.index(marker)
    except ValueError:
        return None

    block_lines: list[str] = []
    brace_depth = 0
    in_multiline_string = False

    for line in text[start:].splitlines():
        block_lines.append(line)

        if not in_multiline_string:
            brace_depth += line.count("{") - line.count("}")
            if brace_depth == 0:
                return "\n".join(block_lines)

        if line.count("''") % 2 == 1:
            in_multiline_string = not in_multiline_string

    return None


def extract_shell_snippet(text: str, marker: str) -> str | None:
    match = re.search(rf"{re.escape(marker)}.*?''(.*?)'';", text, re.S)
    return match.group(1) if match else None


def expect_contains(block: str | None, needle: str, message: str, failures: list[str]) -> None:
    if block is None or needle not in block:
        failures.append(message)


def expect_any_contains(block: str | None, needles: tuple[str, ...], message: str, failures: list[str]) -> None:
    if block is None or not any(needle in block for needle in needles):
        failures.append(message)


darwin = Path("den/aspects/features/darwin-core.nix").read_text()
vm = Path("den/aspects/hosts/vm-aarch64.nix").read_text()
failures: list[str] = []

darwin_key_block = extract_nix_attr_block(darwin, "launchd.user.agents.vm-touchid-bridge-key = {")
expect_contains(
    darwin_key_block,
    "id_ed25519_touchid_bridge_to_vm",
    "darwin should create a dedicated local bridge key at ~/.ssh/id_ed25519_touchid_bridge_to_vm",
    failures,
)
expect_contains(
    darwin_key_block,
    "ssh-keygen",
    "darwin should generate the bridge key with ssh-keygen when it is missing",
    failures,
)
expect_contains(
    darwin_key_block,
    "if [ ! -f",
    "darwin should guard bridge key generation so an existing key is not overwritten",
    failures,
)
expect_contains(
    darwin_key_block,
    "chmod 600",
    "darwin should keep the dedicated bridge key at mode 0600",
    failures,
)

vm_user_key_block = extract_shell_snippet(vm, "home.activation.ensureVmTouchIdBridgeUserKey")
expect_contains(
    vm_user_key_block,
    "id_ed25519_touchid_bridge_to_host",
    "vm Home Manager activation should create ~/.ssh/id_ed25519_touchid_bridge_to_host",
    failures,
)
expect_contains(
    vm_user_key_block,
    "ssh-keygen",
    "vm Home Manager activation should generate the dedicated user bridge key when it is missing",
    failures,
)
expect_contains(
    vm_user_key_block,
    "if [ ! -f",
    "vm Home Manager activation should avoid overwriting an existing user bridge key",
    failures,
)
expect_contains(
    vm_user_key_block,
    "chmod 600",
    "vm Home Manager activation should keep the user bridge key at mode 0600",
    failures,
)

vm_root_key_block = extract_nix_attr_block(vm, "systemd.services.vm-touchid-sudo-bridge-key = {")
expect_any_contains(
    vm_root_key_block,
    ("/var/lib/vm-touchid-sudo-bridge/id_ed25519", "vmTouchIdSudoBridgeKey"),
    "vm should provision a root-owned bridge key at /var/lib/vm-touchid-sudo-bridge/id_ed25519",
    failures,
)
expect_contains(
    vm_root_key_block,
    "ssh-keygen",
    "vm should generate the dedicated root bridge key with ssh-keygen when it is missing",
    failures,
)
expect_contains(
    vm_root_key_block,
    "if [ ! -f",
    "vm root bridge key provisioning should avoid overwriting an existing key",
    failures,
)
expect_contains(
    vm_root_key_block,
    "chmod 600",
    "vm should keep the root bridge key at mode 0600",
    failures,
)

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY
  assert_success \
    || fail "touchid bridge should provision dedicated local ssh identities on Darwin and the VM"
}

# bats test_tags=darwin,home-manager-core,linux-core
@test "touchid bridge tunnels use dedicated ssh identities" {
  local user_tunnel_drv sudo_tunnel_drv

  user_tunnel_drv=$(nix_eval_apply_raw \
    '.#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services."rbw-pinentry-touchid-broker-tunnel".Service.ExecStart' \
    'execStart:
      let
        command = builtins.elemAt execStart 0;
      in
      builtins.head (builtins.attrNames (builtins.getContext command))')

  sudo_tunnel_drv=$(nix_eval_apply_raw \
    '.#nixosConfigurations.vm-aarch64.config.systemd.services.vm-touchid-sudo-broker-tunnel.serviceConfig.ExecStart' \
    'execStart: builtins.head (builtins.attrNames (builtins.getContext execStart))')

  run python - "$user_tunnel_drv" "$sudo_tunnel_drv" <<'PY'
from pathlib import Path
import json
import subprocess
import sys


def derivation_text(drv: str) -> str:
    payload = json.loads(
        subprocess.run(
            ["nix", "derivation", "show", drv],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    return next(iter(payload["derivations"].values()))["env"]["text"]


def extract_nix_attr_block(text: str, marker: str) -> str | None:
    try:
        start = text.index(marker)
    except ValueError:
        return None

    block_lines: list[str] = []
    brace_depth = 0
    in_multiline_string = False

    for line in text[start:].splitlines():
        block_lines.append(line)

        if not in_multiline_string:
            brace_depth += line.count("{") - line.count("}")
            if brace_depth == 0:
                return "\n".join(block_lines)

        if line.count("''") % 2 == 1:
            in_multiline_string = not in_multiline_string

    return None


user_tunnel_drv, sudo_tunnel_drv = sys.argv[1:3]
user_tunnel = derivation_text(user_tunnel_drv)
sudo_tunnel = derivation_text(sudo_tunnel_drv)
darwin = Path("den/aspects/features/darwin-core.nix").read_text()
darwin_tunnel = extract_nix_attr_block(darwin, "launchd.user.agents.vm-touchid-broker-tunnel = {")

failures: list[str] = []

if "/home/m/.ssh/id_ed25519_touchid_bridge_to_host" not in user_tunnel:
    failures.append("vm user touchid tunnel should use ~/.ssh/id_ed25519_touchid_bridge_to_host")

if "/var/lib/vm-touchid-sudo-bridge/id_ed25519" not in sudo_tunnel:
    failures.append("vm root touchid tunnel should use /var/lib/vm-touchid-sudo-bridge/id_ed25519")

if "-i /home/m/.ssh/id_ed25519" in sudo_tunnel:
    failures.append("vm root touchid tunnel should stop using the legacy generic /home/m/.ssh/id_ed25519 key")

if darwin_tunnel is None or darwin_tunnel.count("IdentityFile=/Users/m/.ssh/id_ed25519_touchid_bridge_to_vm") < 2:
    failures.append("darwin touchid bridge tunnel should use /Users/m/.ssh/id_ed25519_touchid_bridge_to_vm for both bridge ssh invocations")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY
  assert_success \
    || fail "touchid bridge tunnels should be rewired onto the dedicated ssh identities"
}

# bats test_tags=darwin,home-manager-core,linux-core
@test "touchid bridge trust artifacts are authorized and installed" {
  run python - <<'PY'
from pathlib import Path
import sys

darwin = Path("den/aspects/features/darwin-core.nix").read_text()
vm = Path("den/aspects/hosts/vm-aarch64.nix").read_text()

checks = [
    (
        'generated.requireFile "mac-host-authorized-keys"',
        darwin,
        "Darwin should keep the existing mac-host-authorized-keys authorization",
    ),
    (
        'generated.requireFile "touchid-bridge-vm-user-to-mac.pub"',
        darwin,
        "Darwin should authorize the VM user touchid bridge key",
    ),
    (
        'generated.requireFile "touchid-bridge-vm-root-to-mac.pub"',
        darwin,
        "Darwin should authorize the VM root touchid bridge key",
    ),
    (
        'generated.requireFile "host-authorized-keys"',
        vm,
        "vm-aarch64 should keep the existing host-authorized-keys authorization",
    ),
    (
        'generated.requireFile "touchid-bridge-mac-to-vm.pub"',
        vm,
        "vm-aarch64 should authorize the Darwin touchid bridge key",
    ),
    (
        'known_hosts_vm_touchid_bridge',
        darwin,
        "Darwin should install a dedicated bridge known_hosts file under ~/.ssh",
    ),
    (
        '192.168.130.3 ${builtins.readFile (generated.requireFile "vm-host-ssh-ed25519.pub")}',
        darwin,
        "Darwin should pin the VM SSH host key for the reverse tunnel",
    ),
    (
        'known_hosts_touchid_bridge',
        vm,
        "vm-aarch64 should install a dedicated user bridge known_hosts file under ~/.ssh",
    ),
    (
        '/var/lib/vm-touchid-sudo-bridge/known_hosts',
        vm,
        "vm-aarch64 should install a root-owned bridge known_hosts file under /var/lib/vm-touchid-sudo-bridge",
    ),
    (
        '192.168.130.1 ${builtins.readFile (generated.requireFile "mac-host-ssh-ed25519.pub")}',
        vm,
        "vm-aarch64 should pin the macOS host SSH key for both bridge clients",
    ),
]

failures = [message for needle, text, message in checks if needle not in text]

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY
  assert_success
}

# bats test_tags=darwin
@test "darwin: macOS touchid broker get-secret reuses the proven rbw description shape" {
  run python - <<'PY'
from pathlib import Path
import sys

text = Path("den/aspects/features/darwin-core.nix").read_text()

required = 'desc = f"SETDESC \\"Bitwarden RBW <{email}>\\" ID {key_id}, Unlock the local database for \'rbw\'"'
if required not in text:
    print("Darwin touchid broker should reuse the working rbw SETDESC shape", file=sys.stderr)
    sys.exit(1)

forbidden = 'f"SETDESC {quote_assuan(desc)}\\n"'
if forbidden in text:
    print("Darwin touchid broker should not wrap the entire rbw SETDESC payload in quote_assuan", file=sys.stderr)
    sys.exit(1)
PY
  assert_success
}

# bats test_tags=darwin
@test "darwin: macOS touchid broker approve uses touchid cache prerequisites" {
  run python - <<'PY'
from pathlib import Path
import sys

text = Path("den/aspects/features/darwin-core.nix").read_text()
start = text.index("def approve(pinentry_program):")
end = text.index("class ThreadedUnixServer", start)
approve = text[start:end]

if 'pinentry.command("OPTION allow-external-password-cache\\n", require_ok=True)' not in approve:
    print("Darwin touchid broker approve should enable allow-external-password-cache", file=sys.stderr)
    sys.exit(1)

if 'SETKEYINFO' not in approve:
    print("Darwin touchid broker approve should send a stable SETKEYINFO before GETPIN", file=sys.stderr)
    sys.exit(1)

required_desc = 'desc = f"SETDESC \\"{APPROVE_DESC}\\" ID {key_id}, Approve a sudo request from the NixOS VM"'
if required_desc not in approve:
    print("Darwin touchid broker approve should keep the stable SETDESC shape", file=sys.stderr)
    sys.exit(1)

if 'desc + "\\n"' not in approve:
    print("Darwin touchid broker approve should send the pre-shaped SETDESC payload directly", file=sys.stderr)
    sys.exit(1)

if 'f"SETDESC {quote_assuan(APPROVE_DESC)}\\n"' in approve:
    print("Darwin touchid broker approve should not regress to quoting the plain APPROVE_DESC payload", file=sys.stderr)
    sys.exit(1)
PY
  assert_success
}

# bats test_tags=darwin,linux-core
@test "docs: touchid bridge generated artifacts are wired into bootstrap and refresh tooling" {
  run python - <<'PY'
from pathlib import Path
import os
import re
import shlex
import subprocess
import sys
import tempfile
import textwrap

macbook = Path("docs/macbook.sh").read_text()
vm = Path("docs/vm.sh").read_text()


FUNCTION_DEFINITION_RE = re.compile(
    r"^[A-Za-z_][A-Za-z0-9_]*\(\) \{\n.*?^\}",
    re.MULTILINE | re.DOTALL,
)


def function_definitions(script: str, required: set[str]) -> str:
    definitions = [match.group(0) for match in FUNCTION_DEFINITION_RE.finditer(script)]
    missing = [name for name in required if not any(defn.startswith(f"{name}()") for defn in definitions)]
    if missing:
        raise ValueError(f"missing shell function definitions: {missing}")
    return "\n\n".join(definitions) + "\n"

failures = []

def run_function(definitions: str, function_name: str, prelude: str, env: dict[str, str]) -> None:
    script = textwrap.dedent(
        f"""\
        set -euo pipefail
        {definitions}
        {prelude}
        {function_name} >/dev/null 2>&1
        """
    )
    result = subprocess.run(["bash", "-c", script], env=env, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"{function_name} harness failed\\nSTDOUT:\\n{result.stdout}\\nSTDERR:\\n{result.stderr}"
        )

def expect_file_content(path: Path, expected: str, message: str) -> None:
    if not path.is_file():
        failures.append(message)
        return
    if path.read_text() != expected:
        failures.append(message)


with tempfile.TemporaryDirectory() as tmpdir_str:
    tmpdir = Path(tmpdir_str)
    home = tmpdir / "home"
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(parents=True)
    host_ssh_dir = tmpdir / "host-ssh"
    host_ssh_dir.mkdir()
    generated_dir = tmpdir / "generated"
    generated_dir.mkdir()
    config_dir = tmpdir / "config"
    config_dir.mkdir()
    bin_dir = tmpdir / "bin"
    bin_dir.mkdir()

    mac_host_key = "ssh-ed25519 AAAA mac-host\n"
    mac_bridge_key = "ssh-ed25519 AAAA mac-bridge\n"
    vm_host_key = "ssh-ed25519 AAAA vm-host\n"
    vm_user_bridge_key = "ssh-ed25519 AAAA vm-user-bridge\n"
    vm_root_bridge_key = "ssh-ed25519 AAAA vm-root-bridge\n"

    host_ssh_pubkey_file = host_ssh_dir / "ssh_host_ed25519_key.pub"
    host_ssh_pubkey_file.write_text(mac_host_key)
    (ssh_dir / "id_ed25519.pub").write_text("ssh-ed25519 AAAA mac-user\n")
    (ssh_dir / "id_ed25519_touchid_bridge_to_vm").write_text("PRIVATE KEY PLACEHOLDER\n")
    (ssh_dir / "id_ed25519_touchid_bridge_to_vm.pub").write_text(mac_bridge_key)

    mock_ssh = bin_dir / "ssh"
    mock_ssh.write_text(
        "#!/bin/sh\n"
        "case \"$*\" in\n"
        "  *age-keygen*) printf 'age1mockkey\\n' ;;\n"
        f"  *'/etc/ssh/ssh_host_ed25519_key.pub'*) printf {shlex.quote(vm_host_key)} ;;\n"
        f"  *'id_ed25519_touchid_bridge_to_host.pub'*) printf {shlex.quote(vm_user_bridge_key)} ;;\n"
        f"  *'/var/lib/vm-touchid-sudo-bridge/id_ed25519.pub'*) printf {shlex.quote(vm_root_bridge_key)} ;;\n"
        "  *) printf 'unexpected ssh invocation: %s\\n' \"$*\" >&2; exit 1 ;;\n"
        "esac\n"
    )
    mock_ssh.chmod(0o755)

    mock_rbw = bin_dir / "rbw"
    mock_rbw.write_text(
        "#!/bin/sh\n"
        "if [ \"$1\" = 'get' ] && [ \"$2\" = 'orbstack-kubeconfig' ]; then\n"
        "  printf 'apiVersion: v1\\nclusters: []\\n'\n"
        "  exit 0\n"
        "fi\n"
        "printf 'unexpected rbw invocation: %s\\n' \"$*\" >&2\n"
        "exit 1\n"
    )
    mock_rbw.chmod(0o755)

    mock_nix = bin_dir / "nix"
    mock_nix.write_text(
        "#!/bin/sh\n"
        "exit 0\n"
    )
    mock_nix.chmod(0o755)

    env = os.environ.copy()
    env["HOME"] = str(home)
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"

    run_function(
        function_definitions(macbook, {"prepare_generated_dataset"}),
        "prepare_generated_dataset",
        textwrap.dedent(
            f"""\
            HOME={shlex.quote(str(home))}
            GENERATED_DIR={shlex.quote(str(generated_dir))}
            HOST_SSH_PUBKEY_FILE={shlex.quote(str(host_ssh_pubkey_file))}
            MAC_HOST_SSH_PUBKEY_FILE={shlex.quote(str(host_ssh_pubkey_file))}
            MAC_TOUCHID_BRIDGE_KEY_FILE={shlex.quote(str(ssh_dir / 'id_ed25519_touchid_bridge_to_vm'))}
            MAC_TOUCHID_BRIDGE_PUBKEY_FILE={shlex.quote(str(ssh_dir / 'id_ed25519_touchid_bridge_to_vm.pub'))}
            die() {{ echo "die:$*" >&2; exit 1; }}
            """
        ),
        env,
    )

    run_function(
        function_definitions(vm, {"cmd_refresh_secrets"}),
        "cmd_refresh_secrets",
        textwrap.dedent(
            f"""\
            HOME={shlex.quote(str(home))}
            GENERATED_DIR={shlex.quote(str(generated_dir))}
            HOST_SSH_PUBKEY_FILE={shlex.quote(str(host_ssh_pubkey_file))}
            MAC_HOST_SSH_PUBKEY_FILE={shlex.quote(str(host_ssh_pubkey_file))}
            NIX_CONFIG_DIR={shlex.quote(str(config_dir))}
            SSH_OPTIONS=
            NIXPORT=22
            NIXUSER=m
            RBW_BIN=rbw
            vm_detect_ip() {{ printf '%s\\n' '192.0.2.10'; }}
            ensure_generated_dir() {{ mkdir -p "$GENERATED_DIR"; }}
            local_wrapper_flake() {{ printf '%s\\n' {shlex.quote(str(tmpdir / 'wrapper'))}; }}
            die() {{ echo "die:$*" >&2; exit 1; }}
            """
        ),
        env,
    )

    expect_file_content(
        generated_dir / "mac-host-ssh-ed25519.pub",
        mac_host_key,
        "docs/macbook.sh should export the macOS host SSH public key into $GENERATED_DIR/mac-host-ssh-ed25519.pub",
    )
    expect_file_content(
        generated_dir / "touchid-bridge-mac-to-vm.pub",
        mac_bridge_key,
        "docs/macbook.sh should copy ~/.ssh/id_ed25519_touchid_bridge_to_vm.pub to $GENERATED_DIR/touchid-bridge-mac-to-vm.pub",
    )
    expect_file_content(
        generated_dir / "vm-host-ssh-ed25519.pub",
        vm_host_key,
        "docs/vm.sh cmd_refresh_secrets() should fetch /etc/ssh/ssh_host_ed25519_key.pub into $GENERATED_DIR/vm-host-ssh-ed25519.pub",
    )
    expect_file_content(
        generated_dir / "touchid-bridge-vm-user-to-mac.pub",
        vm_user_bridge_key,
        "docs/vm.sh cmd_refresh_secrets() should fetch the VM user bridge public key into $GENERATED_DIR/touchid-bridge-vm-user-to-mac.pub",
    )
    expect_file_content(
        generated_dir / "touchid-bridge-vm-root-to-mac.pub",
        vm_root_bridge_key,
        "docs/vm.sh cmd_refresh_secrets() should fetch /var/lib/vm-touchid-sudo-bridge/id_ed25519.pub into $GENERATED_DIR/touchid-bridge-vm-root-to-mac.pub",
    )

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY
  assert_success \
    || fail "bootstrap and refresh tooling should produce the new touchid bridge trust artifacts"
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
@test "wsl: den/aspects/hosts/wsl.nix statically owns repo-specific WSL settings" {
  grep -Fq 'wsl.enable = true;' den/aspects/hosts/wsl.nix
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
@test "wsl: wsl.defaultUser is defined by den provides/wsl.nix (provenance)" {
  local defs
  defs=$(nix_eval_json .#nixosConfigurations.wsl.options.wsl.defaultUser.definitionsWithLocations)
  printf '%s' "$defs" | grep -q 'provides/wsl.nix' \
    || fail "wsl.defaultUser not defined by den provides/wsl.nix; got: $defs"
}

# bats test_tags=wsl
@test "wsl: available option provenance points at den/aspects/hosts/wsl.nix" {
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
@test "gpg: den/aspects/features/git.nix owns GPG config" {
  assert_file_exists den/aspects/features/git.nix
}

# bats test_tags=gpg
@test "gpg: git.nix uses den-native host context (isVM/isDarwin, not currentSystemName)" {
  if grep -Fq 'isVM' den/aspects/features/git.nix; then
    fail 'git.nix must not contain isVM — host-specific config belongs in host aspects'
  fi
  if grep -Fq 'currentSystemName' den/aspects/features/git.nix; then
    fail 'git.nix still uses legacy currentSystemName'
  fi
}

# bats test_tags=gpg
@test "gpg: gpg.nix contains the vm-aarch64 signing key" {
  grep -Fq 'vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";' den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=gpg
@test "gpg: gpg.nix guards VM-only features with isVM" {
  grep -Fq 'allow-preset-passphrase'                           den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'gpgPresetPassphraseLogin'                          den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'systemd.user.services.gpg-preset-passphrase-login' den/aspects/hosts/vm-aarch64.nix
}

# bats test_tags=gpg
@test "gpg: gpg.nix helper script implementation is correct" {
  grep -Fq 'printf '\''%s'\'' "$passphrase" |' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'mapfile -t keygrips < <('          den/aspects/hosts/vm-aarch64.nix
  # The Nix file uses ''${...} escaping inside ''...'' string literals.
  grep -Fq "for keygrip in \"''\${keygrips[@]}\"; do" den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'gpg-preset-passphrase --preset "$keygrip"' den/aspects/hosts/vm-aarch64.nix
  if grep -Fq -- '--passphrase-fd' den/aspects/hosts/vm-aarch64.nix; then
    fail 'helper script still uses unsupported --passphrase-fd'
  fi
  if grep -Fq -- '--passphrase "$passphrase"' den/aspects/hosts/vm-aarch64.nix; then
    fail 'helper script should not expose the passphrase via command-line arguments'
  fi
  if grep -Fq "\$1 == \"grp\" { print \$10; exit }" den/aspects/hosts/vm-aarch64.nix; then
    fail 'helper script still assumes the first grp line is the only relevant keygrip'
  fi
}

# bats test_tags=gpg
@test "gpg: gpg.nix systemd service has retry settings" {
  grep -Fq 'Restart = "on-failure";' den/aspects/hosts/vm-aarch64.nix
  grep -Fq 'RestartSec = 30;'        den/aspects/hosts/vm-aarch64.nix
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
    .generated-input-sentinel/.keep; do
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
  grep -Fq 'yeetnyoink.url' flake.nix
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
@test "generated-input: tests.bats does not hardcode the home-m yeetnyoink fallback" {
  # Split the path so the literal string doesn't appear in this test body
  # and cause a false self-match.
  local bad_pfx bad_sfx
  bad_pfx='/home/m'
  bad_sfx='/Projects/yeetnyoink'
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
  grep -Fq 'external-input-flake.sh' den/aspects/features/shell.nix
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
@test "generated-input: vm-aarch64 host aspect and vm.sh wire the nixos-generated shared folder" {
  grep -Fq '.host:/nixos-generated' den/aspects/hosts/vm-aarch64.nix
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
# bats-package — bats with libraries is wired in devtools
# ===========================================================================

# bats test_tags=bats-package
@test "bats-package: pkgs.bats is not a bare entry in editors or devtools home.packages" {
  if grep -Eq '^[[:space:]]*pkgs\.bats\b' den/aspects/features/editors.nix den/aspects/features/devtools.nix; then
    fail 'pkgs.bats as a bare entry — must use bats.withLibraries'
  fi
}

# bats test_tags=bats-package
@test "bats-package: devtools.nix provides bats with libraries" {
  grep -Fq 'bats.withLibraries' den/aspects/features/devtools.nix
  grep -Fq 'bats-support' den/aspects/features/devtools.nix
  grep -Fq 'bats-assert'  den/aspects/features/devtools.nix
  grep -Fq 'bats-file'    den/aspects/features/devtools.nix
}

# bats test_tags=bats-package
@test "bats-package: devtools.nix provides GNU parallel for bats --jobs" {
  grep -Fq 'pkgs.parallel' den/aspects/features/devtools.nix
}

# bats test_tags=bats-package
@test "bats-package: linux-core.nix does not duplicate bats" {
  if grep -Fq 'bats' den/aspects/features/linux-core.nix; then
    fail 'linux-core.nix still contains bats — moved to devtools.nix'
  fi
}

# bats test_tags=bats-package
@test "bats-package: darwin-core.nix does not duplicate bats" {
  if grep -Fq 'bats' den/aspects/features/darwin-core.nix; then
    fail 'darwin-core.nix still contains bats — moved to devtools.nix'
  fi
}

# bats test_tags=bats-package
@test "bats-package: wsl.nix does not duplicate bats" {
  if grep -Fq 'bats' den/aspects/hosts/wsl.nix; then
    fail 'wsl.nix still contains bats — moved to devtools.nix'
  fi
}
