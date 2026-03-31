# VM GPG Commit Signing Touch ID Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `vm-aarch64` signed Git commits use the macOS host Touch ID flow at commit time, with repo/branch/commit/signer context in the host popup, while falling back to the VM-local pinentry path when the bridge is unavailable.

**Architecture:** Reuse the existing VM user-socket Touch ID broker tunnel instead of introducing a new transport. On the VM, replace the plain GPG signing path with a signing wrapper that captures commit metadata and a bridge pinentry that asks the macOS broker for the passphrase at `GETPIN` time; on macOS, extend the existing broker with a `get-gpg-secret` operation that reuses the `GPG commit signing` helper.

**Tech Stack:** Nix, Home Manager, GPG/gpg-agent, pinentry, Python helper scripts, Swift `LocalAuthentication`, launchd, systemd user services, SSH Unix-socket forwarding, Bats.

---

### Task 0: Create an isolated worktree before implementation

**Files:**
- Create: new git worktree from `main`

**Step 1: Create a fresh worktree**

Use `@using-git-worktrees` to create a dedicated worktree for the VM GPG Touch ID work.

**Step 2: Verify the worktree starts clean**

Run:

```bash
git --no-pager status -sb
git worktree list
```

Expected: the new worktree is on its own branch and starts clean.

**Step 3: Commit**

No commit in this task.

### Task 1: Add the red tests for VM commit-time brokered signing

**Files:**
- Modify: `tests.bats`
- Read: `den/aspects/hosts/vm-aarch64.nix`
- Read: `den/aspects/features/darwin-core.nix`
- Read: `den/aspects/features/git.nix`

**Step 1: Write the failing VM wiring tests**

Add focused GPG-tagged tests that prove:

- VM Git no longer uses plain `${pkgs.gnupg}/bin/gpg` for signing in this mode
- VM `gpg-agent` no longer points directly at `pinentry-tty` in this mode
- VM commit-time pinentry bridge asks the broker first and keeps a local fallback
- Darwin broker exposes a `get-gpg-secret` operation

Use small, source-backed assertions like:

```bash
@test "gpg: vm-aarch64 git signing uses the broker-aware wrapper" {
  actual=$(nix_eval_raw .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.programs.git.settings.gpg.program)
  [[ "$actual" == *vm-gpg-touchid-signing* ]] \
    || fail "vm signing should use the broker-aware wrapper, got '$actual'"
}
```

```bash
@test "gpg: darwin broker exposes get-gpg-secret" {
  grep -Fq 'op == "get-gpg-secret"' den/aspects/features/darwin-core.nix
}
```

**Step 2: Run the targeted tests to verify they fail**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: vm-aarch64 git signing uses the broker-aware wrapper|gpg: vm-aarch64 gpg-agent uses the broker-aware pinentry|gpg: darwin broker exposes get-gpg-secret'
```

Expected: FAIL because none of the new VM signing bridge wiring exists yet.

**Step 3: Commit the red tests**

```bash
git add tests.bats
git commit --no-gpg-sign -m "test: cover vm gpg touchid signing bridge"
```

### Task 2: Add the VM signing wrapper and bridge pinentry with local fallback

**Files:**
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Read: `den/aspects/features/git.nix`
- Test: `tests.bats`

**Step 1: Write the failing wrapper-level test**

Add a Bats helper test that exercises the VM bridge pinentry directly:

- when commit metadata is present, it should contact the broker first
- when the broker returns success, it should return `D <secret>` / `OK`
- when the broker is unreachable, it should forward to the local fallback pinentry

Model the test after the Darwin `rbw-pinentry-touchid` wrapper tests: use fake broker and fake fallback pinentry backends rather than mocks of the logic itself.

**Step 2: Run that wrapper test to verify it fails**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: vm bridge pinentry prefers brokered commit-time secret lookup'
```

Expected: FAIL because the VM bridge pinentry does not exist yet.

**Step 3: Write the VM signing wrapper**

In `den/aspects/hosts/vm-aarch64.nix`, add a VM signing wrapper package that:

- reads the Git/GPG payload on stdin
- derives:
  - payload kind
  - repo name
  - branch
  - commit subject
  - signer name/email
- writes metadata to a VM-local cache path keyed by TTY, following the same pattern already used on Darwin
- execs the real VM GPG binary afterward

Keep the implementation shell-based and close to the Darwin helper shape:

```bash
metadata_file=$(vm_gpg_touchid_metadata_path_for_tty "$tty_name")
printf 'payload_kind=%s\n' "$VM_GPG_TOUCHID_PAYLOAD_KIND" >"$metadata_file"
VM_GPG_TOUCHID_METADATA_PATH="$metadata_file" exec ${pkgs.gnupg}/bin/gpg "$@" <"$payload_file"
```

**Step 4: Write the VM bridge pinentry**

In the same file, add a Python bridge pinentry package that:

- reads the metadata file for commit-time context
- forwards a `{"op":"get-gpg-secret", ...}` request to the existing user-level broker socket
- returns `D <secret>` / `OK` on broker success
- returns an explicit cancel error on broker-side user cancellation
- falls back to the local VM pinentry program on transport or broker errors

**Step 5: Wire VM Git and `gpg-agent` to the new wrapper/pinentry**

Still in `den/aspects/hosts/vm-aarch64.nix`, change the VM-specific overrides so:

- `programs.git.settings.gpg.program` points at the new VM signing wrapper
- `services.gpg-agent.pinentry.package` is replaced by the bridge pinentry package (or `pinentry-program` equivalent if clearer)

**Step 6: Run the targeted tests to verify they pass**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: vm-aarch64 git signing uses the broker-aware wrapper|gpg: vm-aarch64 gpg-agent uses the broker-aware pinentry|gpg: vm bridge pinentry prefers brokered commit-time secret lookup'
```

Expected: PASS.

**Step 7: Commit**

```bash
git add den/aspects/hosts/vm-aarch64.nix tests.bats
git commit --no-gpg-sign -m "feat: bridge vm gpg signing through macos touchid"
```

### Task 3: Extend the macOS broker with `get-gpg-secret`

**Files:**
- Modify: `den/aspects/features/darwin-core.nix`
- Read: `den/aspects/features/git.nix`
- Test: `tests.bats`

**Step 1: Add the failing Darwin broker test**

Add a focused test that proves the broker source handles `op == "get-gpg-secret"` and invokes the GPG helper path rather than the RBW flow.

**Step 2: Run it to verify it fails**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: darwin broker exposes get-gpg-secret'
```

Expected: FAIL because the broker does not yet know about that operation.

**Step 3: Implement the broker operation**

In `den/aspects/features/darwin-core.nix`, extend the broker handler to:

- accept `get-gpg-secret`
- pass commit metadata through to the helper environment
- call the `GPG commit signing` helper
- return `{ "ok": true, "secret": ... }` on success
- return a distinguishable “cancelled” result for explicit Touch ID denial

Keep the request shape explicit:

```python
{
  "op": "get-gpg-secret",
  "metadata": {
    "repo_name": "...",
    "repo_branch": "...",
    "payload_subject": "...",
    "signer_name": "...",
    "signer_email": "..."
  }
}
```

**Step 4: Run the targeted Darwin broker test again**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: darwin broker exposes get-gpg-secret'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add den/aspects/features/darwin-core.nix tests.bats
git commit --no-gpg-sign -m "feat: add gpg secret operation to touchid broker"
```

### Task 4: Remove the long-lived VM preset path from the commit-signing flow

**Files:**
- Modify: `den/aspects/hosts/vm-aarch64.nix`
- Test: `tests.bats`

**Step 1: Add the failing config test**

Add a test that proves this mode no longer relies on the current login-time `gpg-preset-passphrase-login` path for commit signing.

Examples:

```bash
@test "gpg: vm-aarch64 commit-time touchid mode does not keep the login-time preset service enabled" {
  actual=$(nix_generated_eval --json \
    --apply 'services: services ? "gpg-preset-passphrase-login"' \
    .#nixosConfigurations.vm-aarch64.config.home-manager.users.m.systemd.user.services)
  assert_equal "$actual" "false"
}
```

If the final design chooses to keep the service definition around behind a toggle, assert the VM’s active mode disables it.

**Step 2: Run that test to verify it fails**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: vm-aarch64 commit-time touchid mode does not keep the login-time preset service enabled'
```

Expected: FAIL.

**Step 3: Update the VM GPG agent behavior**

Adjust the VM GPG settings so commit-time Touch ID actually happens:

- remove the one-year preset-passphrase assumptions from this mode
- use short-lived or no preset cache for signing
- preserve the local fallback pinentry path when the broker is unavailable

**Step 4: Run the focused VM GPG tests**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'gpg: vm-aarch64 commit-time touchid mode does not keep the login-time preset service enabled|gpg: vm-aarch64 gpg-agent uses the broker-aware pinentry'
```

Expected: PASS.

**Step 5: Commit**

```bash
git add den/aspects/hosts/vm-aarch64.nix tests.bats
git commit --no-gpg-sign -m "refactor: switch vm gpg signing to commit-time touchid"
```

### Task 5: Full verification and live validation

**Files:**
- Verify only unless fixes are needed

**Step 1: Run the full GPG Bats slice**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter-tags gpg
```

Expected: all GPG tests PASS.

**Step 2: Run the Darwin eval gate**

Run:

```bash
cd /path/to/worktree
bats tests.bats --filter 'darwin: macbook-pro-m1 Darwin system settings evaluate correctly'
```

Expected: PASS.

**Step 3: Build Darwin and VM**

Run:

```bash
cd /path/to/worktree
WRAPPER=$(bash scripts/external-input-flake.sh)
NIXPKGS_ALLOW_UNFREE=1 nix build --no-link "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file
NIXPKGS_ALLOW_UNFREE=1 nix build --no-link "path:$WRAPPER#nixosConfigurations.vm-aarch64.config.system.build.toplevel" --no-write-lock-file
```

Expected: both builds PASS.

**Step 4: Live validation**

On macOS, switch the Darwin config from the worktree and restart `gpg-agent` if needed. On the VM, switch the VM config from the same worktree, then run a signed commit in a disposable repo.

Validate:

- host popup title is clearly the GPG commit signing helper
- popup body includes repo / branch / commit / signer
- explicit Touch ID cancel aborts the commit
- broker outage falls back to VM-local prompt instead of hanging

**Step 5: Commit**

```bash
git add den/aspects/hosts/vm-aarch64.nix den/aspects/features/darwin-core.nix tests.bats
git commit --no-gpg-sign -m "test: verify vm gpg touchid signing flow"
```

