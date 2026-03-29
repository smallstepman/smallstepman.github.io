# Touch ID Bridge Hardening Design

Date: 2026-03-29

## Goal

Harden the VM-to-macOS Touch ID bridge so the public repository does not rely on re-trusting SSH peers on every reconnect and so the bridge uses a dedicated SSH trust path instead of the general-purpose user SSH identity.

## Current Weaknesses

- The VM-side tunnel scripts delete known-hosts entries and reconnect with `StrictHostKeyChecking=accept-new`.
- The Darwin reverse-tunnel script does the same for the VM host key.
- The bridge currently reuses general-purpose user SSH trust, including the root-owned sudo tunnel reading a user-home key.
- A compromise of VM user `m` can more easily reuse the same SSH trust material that is also used for normal interactive access.

## Approved Approach

Adopt the strongest hardening path:

1. Create bridge-only SSH client identities for:
   - the VM user `rbw` tunnel,
   - the VM root `sudo` tunnel,
   - the macOS reverse tunnel to the VM.
2. Pin the macOS and VM SSH host keys into bridge-specific `known_hosts` files.
3. Remove all `ssh-keygen -R ...` and `StrictHostKeyChecking=accept-new` behavior from the bridge scripts.
4. Make every bridge SSH invocation explicit and hermetic:
   - `-F /dev/null`
   - `BatchMode=yes`
   - `IdentitiesOnly=yes`
   - `IdentityFile=...`
   - `UserKnownHostsFile=...`
   - `GlobalKnownHostsFile=/dev/null`
   - `StrictHostKeyChecking=yes`
5. Stop using the general-purpose `/home/m/.ssh/id_ed25519` key for the root-owned sudo tunnel.

## Trust Model

This does not try to fully sandbox a compromised `m` account. Instead, it narrows the SSH trust used by the bridge so the Touch ID plumbing is no longer coupled to the user's regular SSH identity and no longer silently re-TOFUs host identity changes.

If a pinned host key changes unexpectedly, the bridge must fail closed and stay down until the pinned material is refreshed intentionally.

## Data and Key Material

The bridge will use dedicated SSH identities whose private keys are stored on the machines that use them:

- VM user bridge client key for the `rbw` tunnel
- VM root bridge client key for the `sudo` tunnel
- macOS bridge client key for the reverse tunnel into the VM

The corresponding public keys and pinned SSH host public keys will be distributed through the existing generated dataset / refresh tooling so the repository can remain public without containing private key material.

## Runtime Behavior

- `rbw` and `sudo` behavior should stay unchanged when the bridge is healthy: both still use macOS Touch ID.
- If the bridge is unavailable, `rbw` still falls back locally and `sudo` still falls back to the VM password path.
- If host identity verification fails, the bridge should not reconnect automatically to the new host key; it should log the verification error and remain down.

## Verification

Add targeted coverage for:

- absence of `ssh-keygen -R`
- absence of `StrictHostKeyChecking=accept-new`
- presence of pinned `UserKnownHostsFile` usage
- presence of explicit bridge `IdentityFile`s for all tunnel directions
- absence of the general-purpose user key in the root-owned sudo tunnel

Then live-verify:

- VM `rbw unlock` still uses Touch ID
- VM `sudo true` still uses Touch ID
- fallback still works when the broker is intentionally unavailable
- a deliberate host-key mismatch fails closed instead of silently re-trusting the peer

## Out of Scope

- Full privilege separation of the `m` account on either machine
- Replacing SSH tunneling with a different transport
- Redesigning the Touch ID prompt UX beyond what is necessary to keep the bridge working
