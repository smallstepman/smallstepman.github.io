# Touch ID Bridge Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Touch ID bridge's re-TOFU SSH behavior with pinned host trust and dedicated bridge-only SSH identities without regressing `rbw` or `sudo`.

**Architecture:** Keep the existing Unix-socket + SSH-tunnel bridge architecture, but narrow its SSH trust plane. Generate bridge-only client keys locally on the machines that use them, export only their public halves plus SSH host public keys into the generated dataset, then rewire every bridge SSH invocation to use explicit `IdentityFile` and pinned `known_hosts` files with `StrictHostKeyChecking=yes`.

**Tech Stack:** NixOS, nix-darwin, Home Manager, OpenSSH, launchd, systemd, Bash, Python helpers, Bats.

---

**Execution notes:**

- Use `@test-driven-development` for Tasks 1-5.
- Use `@verification-before-completion` for Task 6.
- Reuse the approved design in `docs/plans/2026-03-29-touchid-bridge-hardening-design.md`.
- Keep new SSH artifact names stable and descriptive:
  - `mac-host-ssh-ed25519.pub`
  - `vm-host-ssh-ed25519.pub`
  - `touchid-bridge-mac-to-vm.pub`
  - `touchid-bridge-vm-user-to-mac.pub`
  - `touchid-bridge-vm-root-to-mac.pub`

### Task 1: Lock the hardening requirements into failing tests

**Files:**
- Modify: `tests.bats`
- Read: `den/aspects/hosts/vm-aarch64.nix`
- Read: `den/aspects/features/darwin-core.nix`
- Read: `docs/vm.sh`
- Read: `docs/macbook.sh`

**Step 1: Write the failing VM tunnel hardening test**

Add a Bats test that inspects the VM tunnel script text and requires:

- no `ssh-keygen -R`
- no `StrictHostKeyChecking=accept-new`
- explicit `-F /dev/null`
- explicit `BatchMode=yes`
- explicit `IdentitiesOnly=yes`
- explicit `UserKnownHostsFile`
- explicit `GlobalKnownHostsFile=/dev/null`
- explicit `StrictHostKeyChecking=yes`
- a dedicated bridge `IdentityFile` for the user `rbw` tunnel
- a dedicated root-owned bridge `IdentityFile` for the sudo tunnel

**Step 2: Write the failing Darwin reverse-tunnel hardening test**

Add a Bats test that inspects `den/aspects/features/darwin-core.nix` and requires the same fail-closed SSH posture for the reverse tunnel into the VM:

- no `ssh-keygen -R`
- no `StrictHostKeyChecking=accept-new`
- explicit `-F /dev/null`
- explicit `BatchMode=yes`
- explicit `IdentitiesOnly=yes`
- explicit bridge `IdentityFile`
- explicit pinned `UserKnownHostsFile`
- explicit `GlobalKnownHostsFile=/dev/null`
- explicit `StrictHostKeyChecking=yes`

**Step 3: Write the failing generated-artifacts test**

Add a Bats test that checks the refresh/bootstrap tooling mentions and produces the new bridge trust artifacts:

- `mac-host-ssh-ed25519.pub`
- `vm-host-ssh-ed25519.pub`
- `touchid-bridge-mac-to-vm.pub`
- `touchid-bridge-vm-user-to-mac.pub`
- `touchid-bridge-vm-root-to-mac.pub`

**Step 4: Run the targeted tests to prove they fail**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
bats -f 'touchid bridge.*hardening|touchid bridge.*generated artifacts|linux: vm-aarch64 sudo touchid bridge uses a root-trusted broker tunnel' tests.bats
```

Expected: at least one FAIL because the tunnel scripts still use re-TOFU SSH settings and no bridge-only trust artifacts exist yet.

**Step 5: Commit the red test state**

```bash
git add tests.bats
git commit -m "test: cover touchid bridge ssh hardening"
```

### Task 2: Create bridge-only SSH identities locally

**Files:**
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `den/aspects/features/darwin-core.nix`
- Modify: `tests.bats`

**Step 1: Add the failing local-key wiring test if Task 1 did not already cover it**

If needed, add/extend tests so the evaluated config proves these private-key paths exist in the design:

- VM user tunnel key: `~/.ssh/id_ed25519_touchid_bridge_to_host`
- VM root tunnel key: `/var/lib/vm-touchid-sudo-bridge/id_ed25519`
- macOS reverse-tunnel key: `~/.ssh/id_ed25519_touchid_bridge_to_vm`

**Step 2: Add macOS local key creation**

In `den/aspects/features/darwin-core.nix`, add a user-side activation step (or a launchd-safe one-shot helper if activation is cleaner) that generates `~/.ssh/id_ed25519_touchid_bridge_to_vm` if it is missing, keeps permissions at `0600`, and never overwrites an existing key.

**Step 3: Add VM user local key creation**

In `den/aspects/hosts/vm-aarch64.nix`, add a Home Manager activation step that generates `~/.ssh/id_ed25519_touchid_bridge_to_host` if it is missing and keeps permissions at `0600`.

**Step 4: Add VM root local key creation**

In `den/aspects/hosts/vm-aarch64.nix`, add a root-managed path for the sudo tunnel key, such as `/var/lib/vm-touchid-sudo-bridge/id_ed25519`, using a root-owned oneshot or activation-safe service so the private key is generated if missing and not stored in `/home/m`.

**Step 5: Run the targeted tests**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
bats -f 'touchid bridge.*hardening|touchid bridge.*generated artifacts' tests.bats
```

Expected: the key-path assertions move to PASS, while artifact-export assertions may still fail until Task 3 lands.

**Step 6: Commit**

```bash
git add den/aspects/hosts/vm-aarch64.nix den/aspects/features/darwin-core.nix tests.bats
git commit -m "feat: add bridge-only ssh identities"
```

### Task 3: Export public bridge trust material into the generated dataset

**Files:**
- Modify: `docs/vm.sh`
- Modify: `docs/macbook.sh`
- Modify: `docs/secrets.md`
- Modify: `docs/index.html`
- Modify: `tests.bats`

**Step 1: Extend macOS bootstrap dataset prep**

In `docs/macbook.sh`, update `prepare_generated_dataset()` so it ensures the macOS bridge key exists and exports these public files into `"$GENERATED_DIR"`:

- `mac-host-ssh-ed25519.pub` from the macOS host SSH public key
- `touchid-bridge-mac-to-vm.pub` from `~/.ssh/id_ed25519_touchid_bridge_to_vm.pub`

Keep the existing `host-authorized-keys`, `mac-host-authorized-keys`, and `secrets.yaml` behavior intact unless a later task deliberately removes/replaces it.

**Step 2: Extend `docs/vm.sh refresh-secrets`**

Teach `cmd_refresh_secrets()` to fetch and/or export:

- `vm-host-ssh-ed25519.pub`
- `touchid-bridge-vm-user-to-mac.pub`
- `touchid-bridge-vm-root-to-mac.pub`

Fetch these over SSH from the VM after ensuring the keys exist. Keep the existing `vm-age-pubkey` and secret refresh flow intact.

**Step 3: Document the new generated files**

Update `docs/secrets.md` and `docs/index.html` so the generated dataset description and `refresh-secrets` help text mention the new pinned host-key and bridge-public-key artifacts.

**Step 4: Run the targeted tests**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
bats -f 'touchid bridge.*generated artifacts' tests.bats
```

Expected: PASS for the generated-artifact coverage.

**Step 5: Commit**

```bash
git add docs/vm.sh docs/macbook.sh docs/secrets.md docs/index.html tests.bats
git commit -m "feat: export touchid bridge trust artifacts"
```

### Task 4: Authorize bridge-only keys and install pinned host keys

**Files:**
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `den/aspects/features/darwin-core.nix`
- Modify: `tests.bats`

**Step 1: Authorize the VM bridge keys on macOS**

In `den/aspects/features/darwin-core.nix`, extend `users.users.m.openssh.authorizedKeys.keyFiles` so the macOS host trusts:

- `generated.requireFile "touchid-bridge-vm-user-to-mac.pub"`
- `generated.requireFile "touchid-bridge-vm-root-to-mac.pub"`

Leave existing interactive access working unless you intentionally replace it in a separate task.

**Step 2: Authorize the macOS bridge key on the VM**

In `den/aspects/hosts/vm-aarch64.nix`, extend `users.users.m.openssh.authorizedKeys.keyFiles` so the VM trusts:

- `generated.requireFile "touchid-bridge-mac-to-vm.pub"`

**Step 3: Install pinned host-key files**

In the same two Nix files, install bridge-specific `known_hosts` content from:

- `generated.requireFile "mac-host-ssh-ed25519.pub"` for VM-side clients
- `generated.requireFile "vm-host-ssh-ed25519.pub"` for the Darwin reverse-tunnel client

Use file locations that match the privilege boundary:

- user-owned `known_hosts` for the VM user `rbw` tunnel
- root-owned pinned `known_hosts` for the VM sudo tunnel
- user-owned pinned `known_hosts` for the Darwin reverse tunnel

**Step 4: Run the targeted tests**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
bats -f 'touchid bridge.*hardening|touchid bridge.*generated artifacts' tests.bats
```

Expected: PASS for the authorization and pinned-host-key assertions.

**Step 5: Commit**

```bash
git add den/aspects/hosts/vm-aarch64.nix den/aspects/features/darwin-core.nix tests.bats
git commit -m "feat: pin touchid bridge host trust"
```

### Task 5: Rewire the tunnel commands to fail closed

**Files:**
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Modify: `den/aspects/features/darwin-core.nix`
- Modify: `tests.bats`

**Step 1: Harden the VM user `rbw` tunnel command**

Update `mkRbwPinentryTouchIdBrokerTunnel` so it:

- removes `ssh-keygen -R`
- removes `StrictHostKeyChecking=accept-new`
- adds `-F /dev/null`
- adds `BatchMode=yes`
- adds `IdentitiesOnly=yes`
- uses `IdentityFile=~/.ssh/id_ed25519_touchid_bridge_to_host`
- uses the pinned `UserKnownHostsFile`
- uses `GlobalKnownHostsFile=/dev/null`
- uses `StrictHostKeyChecking=yes`

**Step 2: Harden the VM root `sudo` tunnel command**

Update `mkVmTouchIdSudoBrokerTunnel` so it:

- no longer uses `/home/m/.ssh/id_ed25519`
- uses the root-owned bridge key
- uses the root-owned pinned `known_hosts`
- keeps the root-owned socket behavior intact
- uses the same fail-closed SSH options as Step 1

**Step 3: Harden the Darwin reverse tunnel command**

Update `launchd.user.agents.vm-touchid-broker-tunnel` so it:

- removes `ssh-keygen -R`
- removes `StrictHostKeyChecking=accept-new`
- uses `-F /dev/null`
- uses `BatchMode=yes`
- uses `IdentitiesOnly=yes`
- uses `IdentityFile=~/.ssh/id_ed25519_touchid_bridge_to_vm`
- uses the pinned VM `UserKnownHostsFile`
- uses `GlobalKnownHostsFile=/dev/null`
- uses `StrictHostKeyChecking=yes`

**Step 4: Run the targeted tests**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
bats -f 'touchid bridge.*hardening|linux: vm-aarch64 sudo touchid bridge runs pam_exec with seteuid|darwin: evaluated macOS touchid broker agent is wired' tests.bats
```

Expected: PASS for the hardened SSH posture without regressing the existing sudo/rbw bridge coverage.

**Step 5: Commit**

```bash
git add den/aspects/hosts/vm-aarch64.nix den/aspects/features/darwin-core.nix tests.bats
git commit -m "feat: harden touchid bridge ssh clients"
```

### Task 6: Verify fail-closed behavior and live flows

**Files:**
- Read: `docs/plans/2026-03-29-touchid-bridge-hardening-design.md`
- Read: `docs/vm.sh`
- Test: `tests.bats`

**Step 1: Run the focused verification suite**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
bats -f 'touchid bridge.*hardening|touchid bridge.*generated artifacts|vm: vm-aarch64 evaluated rbw pinentry derivation encodes touchid bridge fallback|linux: vm-aarch64 sudo uses macOS touchid bridge|linux: vm-aarch64 sudo touchid bridge runs pam_exec with seteuid|darwin: macOS touchid broker get-secret reuses the proven rbw description shape|darwin: macOS touchid broker approve uses touchid cache prerequisites' tests.bats
```

Expected: all tests PASS.

**Step 2: Apply Darwin and VM from the worktree**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
WRAPPER=$(bash scripts/external-input-flake.sh)
NIXPKGS_ALLOW_UNFREE=1 nix build "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file
sudo ./result/sw/bin/darwin-rebuild switch --flake "path:$WRAPPER#macbook-pro-m1" --no-write-lock-file
```

Then in the VM worktree:

```bash
cd /nixos-config/.worktrees/vm-macos-touchid-bridge
WRAPPER=$(NIX_CONFIG_DIR=$PWD GENERATED_INPUT_DIR=/nixos-generated bash scripts/external-input-flake.sh)
sudo NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nixos-rebuild switch --flake "path:$WRAPPER#vm-aarch64" --no-write-lock-file
```

Expected: both applies succeed.

**Step 3: Re-run the live happy-path checks**

Run:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
NIX_CONFIG_DIR="$PWD" bash docs/vm.sh ssh 'rbw stop-agent >/dev/null 2>&1 || true; rbw lock >/dev/null 2>&1 || true; rbw unlock'
```

Then:

```bash
cd /Users/m/.config/nix/.worktrees/vm-macos-touchid-bridge
addr=$(NIX_CONFIG_DIR="$PWD" bash docs/vm.sh ip)
ssh -tt -o StrictHostKeyChecking=accept-new -p22 "m@$addr" 'sudo -k; sudo true'
```

Expected: both still use Touch ID.

**Step 4: Prove host-key mismatch fails closed without mutating the running bridge**

From the VM, create a temporary bad `known_hosts` file and use the same SSH options as the hardened tunnel command:

```bash
tmp=$(mktemp)
printf '192.168.130.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBADKEYBADKEYBADKEYBADKEYBADKEYBADKEYBADKEY\n' > "$tmp"
ssh -F /dev/null \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile="$tmp" \
  -o GlobalKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=yes \
  -i ~/.ssh/id_ed25519_touchid_bridge_to_host \
  m@192.168.130.1 true
rm -f "$tmp"
```

Expected: FAIL with `Host key verification failed` or a direct host-key mismatch error, not a new trust prompt.

**Step 5: Commit any final verification-driven fixups**

```bash
git add den/aspects/hosts/vm-aarch64.nix den/aspects/features/darwin-core.nix docs/vm.sh docs/macbook.sh docs/secrets.md docs/index.html tests.bats
git commit -m "fix: finalize touchid bridge ssh hardening"
```

If Step 5 is a true no-op because verification found nothing else to change, do not create a no-op commit.
