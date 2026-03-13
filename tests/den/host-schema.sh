#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

grep -Fq 'den.hosts.aarch64-linux.vm-aarch64.users.m' den/hosts.nix
grep -Fq 'den.hosts.aarch64-darwin.macbook-pro-m1.users.m' den/hosts.nix
grep -Fq 'den.hosts.x86_64-linux.wsl.users.m' den/hosts.nix
grep -Fq 'options.profile' den/default.nix
grep -Fq 'options.vmware.enable' den/default.nix
grep -Fq 'options.wsl.enable' den/default.nix
grep -Fq 'options.graphical.enable' den/default.nix
grep -A4 'options\.profile' den/default.nix | grep -Fq 'description'
