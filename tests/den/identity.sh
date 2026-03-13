#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# --- Static structure checks ---

# identity feature aspect must include the key user-context batteries
grep -Fq 'den.provides.define-user' den/aspects/features/identity.nix
grep -Fq 'den.provides.primary-user' den/aspects/features/identity.nix
grep -Fq 'den.provides.user-shell' den/aspects/features/identity.nix

# user m aspect must reference the identity aspect
grep -Fq 'den.aspects.identity' den/aspects/users/m.nix

# vm-aarch64 host aspect must include the hostname battery
grep -Fq 'den.provides.hostname' den/aspects/hosts/vm-aarch64.nix

# hosts.nix must carry the explicit vm-macbook hostname
grep -Fq 'vm-macbook' den/hosts.nix

# host aspect files must exist for all three hosts
test -f den/aspects/hosts/macbook-pro-m1.nix
test -f den/aspects/hosts/wsl.nix

# --- Live nix eval checks ---

actual=$(nix eval --raw .#nixosConfigurations.vm-aarch64.config.networking.hostName 2>/dev/null)
expected="vm-macbook"
if [ "$actual" != "$expected" ]; then
  echo "FAIL: vm-aarch64 hostName: expected '$expected', got '$actual'" >&2
  exit 1
fi

actual=$(nix eval --raw .#darwinConfigurations.macbook-pro-m1.config.system.primaryUser 2>/dev/null)
expected="m"
if [ "$actual" != "$expected" ]; then
  echo "FAIL: macbook-pro-m1 primaryUser: expected '$expected', got '$actual'" >&2
  exit 1
fi

actual=$(nix eval --raw .#nixosConfigurations.wsl.config.wsl.defaultUser 2>/dev/null)
expected="m"
if [ "$actual" != "$expected" ]; then
  echo "FAIL: wsl defaultUser: expected '$expected', got '$actual'" >&2
  exit 1
fi

echo "All identity checks passed."
