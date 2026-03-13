#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

grep -Fq 'inputs.den.url = "github:vic/den";' flake.nix
grep -Fq 'inputs.den.flakeModule' den/default.nix
grep -Fq 'den.provides.import-tree' den/legacy.nix
grep -Fq 'inherit (den.flake) nixosConfigurations darwinConfigurations;' flake.nix

# flake-aspects was removed from flake.nix; the lock file must not retain a
# stale root-level entry for it (would indicate lock/flake.nix divergence).
python3 - <<'PYEOF'
import json, sys
with open("flake.lock") as f:
    lock = json.load(f)
root_inputs = lock["nodes"]["root"].get("inputs", {})
if "flake-aspects" in root_inputs:
    print("FAIL: flake.lock root still contains stale 'flake-aspects' input", file=sys.stderr)
    sys.exit(1)
PYEOF
