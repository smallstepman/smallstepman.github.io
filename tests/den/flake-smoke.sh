#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

grep -Fq 'inputs.den.url = "github:vic/den";' flake.nix
grep -Fq 'inputs.den.flakeModule' den/default.nix
grep -Fq 'den.provides.import-tree' den/legacy.nix
grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' flake.nix
