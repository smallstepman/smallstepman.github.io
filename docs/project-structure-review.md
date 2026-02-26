# Project Structure Review (Pedantic + Pragmatic)

This review focuses on future growth to more target hardware (`rpi`, `vps`, GPU servers), where many hosts will **not** use most of the desktop-heavy `home-manager` setup.

## Current strengths

- `lib/mksystem.nix` is a good single entry point for assembling systems.
- `machines/` and `users/` are already separated.
- Platform flags (`darwin`, `isWSL`, Linux) are explicit and easy to reason about.

## Pedantic lens (what looks inconsistent or out of place)

1. `users/m/home-manager.nix` is large and carries many cross-platform concerns in one place, which makes future host-specific pruning hard.
2. `machines/vm-shared.nix` name reads as VM-only but also holds choices that look like reusable Linux profile behavior.
3. `patches/` currently mixes patch intent types (platform workaround, app-level patch, clipboard patch) without a naming/category convention.
4. `docs/README` says docs are mostly for GitHub Pages scripts, but the repo now also benefits from architecture notes; this should be explicit.

## Pragmatic lens (what keeps code searchable/debuggable)

Keep the current top-level layout (`lib/`, `machines/`, `users/`, `patches/`, `docs/`) because it is already familiar and grep-friendly, but make host-profile intent easier to discover:

- Prefer **profile directories** over condition-heavy single files.
- Keep one-file-per-concern for fast `rg`/navigation.
- Use consistent naming that encodes scope (`base`, `desktop`, `headless`, `hardware-*`).

## Recommended target layout (incremental, no big-bang rewrite)

### 1) Host profiles for machines

```text
machines/
  profiles/
    base.nix
    desktop.nix
    headless.nix
    gpu.nix
  vm-aarch64.nix
  wsl.nix
  macbook-pro-m1.nix
```

Rationale: adding `rpi`/`vps`/GPU hosts becomes mostly profile composition instead of copying and deleting desktop options.

### 2) Profile split for home-manager

```text
users/m/
  home-manager.nix
  home-manager/
    base.nix
    desktop.nix
    headless.nix
    darwin.nix
```

Rationale: hardware that only needs shells/dev tools can import `base + headless` and skip heavy desktop/UI config.

### 3) Patch taxonomy by intent

```text
patches/
  platform/
  apps/
  integrations/
```

Rationale: helps quickly answer “why does this patch exist?” during debugging.

## Minimal migration order

1. Introduce `machines/profiles/base.nix` and move only truly shared machine config there.
2. Add `users/m/home-manager/base.nix` and move a small, obvious block first (shell/core CLI tools).
3. Keep old files as wrappers importing new profile files until stable.
4. Move patch files into categorized folders last (mechanical change).

This preserves current behavior while making future hardware additions straightforward.
