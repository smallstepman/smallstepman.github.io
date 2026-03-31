# YNY warm-helper nix-darwin design

## Problem

`skhd` currently calls the local development build of `yny` directly for directional focus and move:

- binary: `/Users/m/.cargo/target/release/yny`
- config: `/Users/m/yny.config.dev.toml`

The new warm-helper path should be wired into the macOS desktop config so focus hotkeys can use a persistent helper process without changing the existing local-development workflow.

## Goals

- Run the warm helper as a managed per-user `launchd` service.
- Keep using the current local development binary and config path.
- Route only `focus` hotkeys through the helper.
- Leave `move` bindings daemonless for now.
- Make failures visible instead of silently falling back.

## Chosen approach

Use an always-on `launchd.user.agents.yny-warm-helper` entry in `den/aspects/features/darwin-desktop.nix`, and update the four focus bindings in `dotfiles/by-host/darwin/skhdrc` to set `YNY_WARM_HELPER_SOCKET=/tmp/yny-warm.sock`.

### Service shape

- file: `den/aspects/features/darwin-desktop.nix`
- label: `yny-warm-helper`
- command:
  - `/Users/m/.cargo/target/release/yny`
  - `--config /Users/m/yny.config.dev.toml`
  - `warm-helper serve --socket /tmp/yny-warm.sock`
- launchd behavior:
  - `RunAtLoad = true`
  - `KeepAlive = true`
  - `LimitLoadToSessionType = "Aqua"`
  - `ProcessType = "Interactive"`
- logs:
  - `StandardOutPath = "/tmp/yny-warm-helper.log"`
  - `StandardErrorPath = "/tmp/yny-warm-helper.log"`

### Hotkey shape

- file: `dotfiles/by-host/darwin/skhdrc`
- change only the four `focus` commands
- prefix them with `YNY_WARM_HELPER_SOCKET=/tmp/yny-warm.sock`
- leave the four `move` commands unchanged

## Why this approach

This keeps the rollout small and predictable:

- it matches the current local-binary workflow already used by `skhd`
- it avoids a wrapper layer for the first pass
- it avoids setting the helper socket globally, which could accidentally route unsupported commands through the helper
- it keeps the change localized to the Darwin desktop integration points that already own `skhd`

## Alternatives considered

### Launchd agent plus shared wrapper command

This would reduce repetition in `skhdrc`, but it introduces an extra abstraction layer for a small first-pass change.

### On-demand wrapper from `skhd`

This could try to start or heal the helper from the hotkey path, but it adds shell complexity, concurrent-start races, and cold-path latency exactly where the helper is meant to reduce latency.

## Failure model

- If the helper is unavailable, focus hotkeys should fail loudly.
- There should be no silent fallback to daemonless focus when the socket variable is set.
- Because the service runs the local release binary directly, a fresh `cargo build --release` does not replace the already-running helper process; the user must restart the agent to pick up the new binary.

## Verification

After applying the Nix changes:

1. Run `darwin-rebuild switch`.
2. Confirm the user agent is loaded.
3. Confirm `/tmp/yny-warm.sock` exists.
4. Confirm `/tmp/yny-warm-helper.log` is being written.
5. Manually test the four directional focus hotkeys.
6. Confirm the move hotkeys still use the daemonless path.

## Future cleanup

If the first pass works well, a later refactor can centralize the repeated `yny` command prefix in `skhdrc` behind a wrapper or generated binding helper. That is intentionally out of scope for this initial integration.
