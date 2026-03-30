# VM GPG Commit Signing via macOS Touch ID

## Goal

Make `vm-aarch64` signed Git commits use the macOS host Touch ID flow at commit time, with the same repo/branch/commit/signer context shown in the host popup.

## Current state

- Darwin already has a commit-signing wrapper that captures Git metadata and rewrites the local Touch ID prompt.
- The VM currently uses local GPG with:
  - `programs.git.settings.gpg.program = "${pkgs.gnupg}/bin/gpg"`
  - `services.gpg-agent.pinentry.package = pkgs.pinentry-tty`
  - `allow-preset-passphrase`
  - a login-time `gpg-preset-passphrase-login` service that fetches the passphrase from `rbw` and caches it for a long time.
- The existing VM↔macOS bridge already supports hardened user-socket transport for `rbw` and root-socket approval for `sudo`.

## Chosen approach

Use the existing user-level VM↔macOS broker tunnel for a new commit-time GPG secret flow.

- On the VM, replace the plain GPG signing path with:
  - a signing wrapper that captures commit metadata at Git invocation time
  - a bridge pinentry that asks the macOS broker for the GPG passphrase when `GETPIN` happens
- On macOS, extend the existing broker with a `get-gpg-secret` operation that invokes the existing `GPG commit signing` Touch ID helper and returns the signing passphrase over the broker socket.

## Architecture

### VM side

- Add a VM signing wrapper that mirrors the Darwin metadata capture flow:
  - payload kind
  - repo name
  - branch
  - commit subject
  - signer name/email
- Switch the VM `gpg-agent` pinentry from plain `pinentry-tty` to a VM bridge wrapper.
- The VM bridge wrapper should:
  - try the macOS broker first for commit-signing requests
  - fail closed on explicit Touch ID cancel
  - fall back to the local VM pinentry path when the broker/tunnel is unavailable or errors

### macOS side

- Extend the existing broker service with a `get-gpg-secret` operation.
- Reuse the existing `GPG commit signing` helper bundle so the host popup keeps the same UX as native Darwin signing.
- Broker returns the passphrase only over the existing hardened Unix-socket SSH tunnel.

## Runtime behavior

### Commit-time prompting

The VM should prompt at commit time, not once per login/session.

That means the current login-time `gpg-preset-passphrase-login` flow cannot remain the primary path for the VM signing key in this mode. The VM signing path should use a short-lived or non-preset cache so each signed commit reaches the brokered Touch ID flow.

### Fallbacks

- **Broker unavailable / tunnel down / helper execution error**
  - fall back to the VM-local pinentry flow
- **User cancels the macOS Touch ID prompt**
  - abort the commit
  - do not fall back locally
- **Broker success**
  - pass the secret back to the VM GPG flow and continue the commit

## Security model

- Reuse the existing hardened bridge transport:
  - dedicated bridge identity
  - pinned host keys
  - hermetic SSH invocation
  - Unix socket transport
- Preserve the current repo’s bridge philosophy:
  - local fallback on infrastructure failure
  - explicit denial on user cancellation
- Avoid storing new long-lived copies of the passphrase on the VM in this mode.

## Testing strategy

- Add VM signing-wrapper tests that prove commit metadata is emitted for the bridge path.
- Add VM bridge-pinentry tests that prove:
  - commit requests go to the broker first
  - cancel fails closed
  - transport/helper failures fall back locally
- Add config tests that prove the VM no longer relies on the login-time preset-passphrase path for this mode.
- Add Darwin broker tests that prove `get-gpg-secret` is exposed and wired to the GPG helper.

## Files most likely to change

- `den/aspects/hosts/vm-aarch64.nix`
- `den/aspects/features/darwin-core.nix`
- `den/aspects/features/git.nix`
- `tests.bats`

