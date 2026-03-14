#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"

# shellcheck source=../lib/generated-input.sh
. "$repo_root/tests/lib/generated-input.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tracked_generated=$(git ls-files 'generated/*')
if [ -n "$tracked_generated" ]; then
  fail "generated/ artifacts are still tracked in git"
fi

for sentinel in \
  .generated-input-sentinel/.keep \
  .yeet-and-yoink-input-sentinel/.keep; do
  git ls-files --error-unmatch "$sentinel" >/dev/null 2>&1 \
    || fail "sentinel placeholder is not tracked: $sentinel"
done

if rg -n 'nix_generated_eval[[:space:]]+\-\-impure|nix[[:space:]].*\-\-impure' tests/den tests/gpg-preset-passphrase.sh >/dev/null; then
  fail 'tests still rely on --impure instead of explicit generated/yeet inputs'
fi

grep -Fq 'inputs.generated = {' flake.nix \
  || fail 'flake.nix must declare an external generated input'
grep -Fq 'flake = false;' flake.nix \
  || fail 'flake.nix must declare generated as a raw non-flake input'

if rg -n '../../../generated/' \
  den/aspects/features/secrets.nix \
  den/aspects/features/darwin-core.nix \
  den/aspects/hosts/vm-aarch64.nix >/dev/null; then
  fail 'den aspects still read repo-relative generated/ paths'
fi

grep -Fq -- '--override-input generated' docs/macbook.sh \
  || fail 'docs/macbook.sh must pass the external generated input'
grep -Fq -- '--override-input generated' docs/vm.sh \
  || fail 'docs/vm.sh must pass the external generated input'
grep -Fq -- '--override-input generated' den/aspects/features/shell-git.nix \
  || fail 'shell-git aliases must pass the external generated input'
if rg -n -- '--impure' AGENTS.md >/dev/null; then
  fail 'AGENTS.md must not document --impure for flake-aware commands'
fi
grep -Fq 'nix build --override-input generated "path:$HOME/.local/share/nix-config-generated" --override-input yeetAndYoink "git+file://$HOME/Projects/yeet-and-yoink?dir=plugins/zellij-break" .#nixosConfigurations.vm-aarch64.config.system.build.toplevel' AGENTS.md \
  || fail 'AGENTS.md must show both external inputs for VM build commands'
grep -Fq 'GENERATED_REF="path:$HOME/.local/share/nix-config-generated"' AGENTS.md \
  || fail 'AGENTS.md must define a generated input reference for direct VM commands'
grep -Fq 'YEET_AND_YOINK_REF="git+file://$HOME/Projects/yeet-and-yoink?dir=plugins/zellij-break"' AGENTS.md \
  || fail 'AGENTS.md must define a yeet-and-yoink input reference for direct VM commands'
grep -Fq 'nixos-rebuild dry-run --flake .#vm-aarch64 --override-input generated "$GENERATED_REF" --override-input yeetAndYoink "$YEET_AND_YOINK_REF"' AGENTS.md \
  || fail 'AGENTS.md must show both external inputs for VM dry-run commands'
grep -Fq 'nixos-rebuild build --flake .#vm-aarch64 --override-input generated "$GENERATED_REF" --override-input yeetAndYoink "$YEET_AND_YOINK_REF"' AGENTS.md \
  || fail 'AGENTS.md must show both external inputs for VM rebuild commands'
grep -Fq 'sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-pro-m1 --override-input generated "path:$HOME/.local/share/nix-config-generated"' AGENTS.md \
  || fail 'AGENTS.md must show the pure generated input for Darwin rebuild commands'
grep -Fq 'sudo nixos-rebuild switch --flake .#vm-aarch64 --specialisation gnome-ibus --override-input generated "path:$HOME/.local/share/nix-config-generated" --override-input yeetAndYoink "git+file://$HOME/Projects/yeet-and-yoink?dir=plugins/zellij-break"' AGENTS.md \
  || fail 'AGENTS.md must show both external inputs for VM specialisation commands'
grep -Fq 'default_nix_config_dir()' docs/macbook.sh \
  || fail 'docs/macbook.sh must default NIX_CONFIG_DIR from the script checkout when available'
grep -Fq 'default_nix_config_dir()' docs/vm.sh \
  || fail 'docs/vm.sh must default NIX_CONFIG_DIR from the script checkout when available'
if rg -n '/home/m/Projects/yeet-and-yoink' tests/lib/generated-input.sh >/dev/null; then
  fail 'tests/lib/generated-input.sh must not fall back to /home/m/Projects/yeet-and-yoink'
fi

grep -Fq '.host:/nixos-generated' den/aspects/features/vmware.nix \
  || fail 'vmware aspect must mount the generated shared folder'
grep -Fq 'guestName = "nixos-generated"' docs/vm.sh \
  || fail 'docs/vm.sh must configure a nixos-generated shared folder'
grep -Fq 'vmrun -T fusion setSharedFolderState "$vmx" "$share_name" "$host_path" writable' docs/vm.sh \
  || fail 'docs/vm.sh must update shared-folder host paths for existing VMs'
grep -Fq 'vmrun -T fusion addSharedFolder "$vmx" "$share_name" "$host_path"' docs/vm.sh \
  || fail 'docs/vm.sh must add missing shared folders for existing VMs'
grep -Fq 'vm_ensure_required_shared_folders "$existing_vmx"' docs/vm.sh \
  || fail 'docs/vm.sh must reconcile shared folders before reusing an existing VM'
grep -Fq 'vm_ensure_required_shared_folders "$vmx"' docs/vm.sh \
  || fail 'docs/vm.sh must reconcile shared folders before switching the VM'

generated_input_dir >/dev/null

actual=$(nix_generated_eval \
  --raw \
  .#nixosConfigurations.vm-aarch64.config.sops.defaultSopsFile)

printf '%s' "$actual" | grep -q 'secrets.yaml' \
  || fail "sops.defaultSopsFile did not resolve through the external generated input"

printf 'PASS: pure external generated input wiring looks correct\n'
