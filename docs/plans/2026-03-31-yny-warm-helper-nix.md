# YNY Warm-Helper Nix Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire the macOS warm-helper into the nix-darwin desktop config so directional focus hotkeys use a launchd-managed helper while move hotkeys stay on the existing daemonless path.

**Architecture:** Keep the integration at the Darwin desktop layer. Add a `launchd.user.agents.yny-warm-helper` service in `den/aspects/features/darwin-desktop.nix` that runs the existing local `yny` release binary with the existing dev config and a fixed Unix socket, then update only the four `focus` bindings in `dotfiles/by-host/darwin/skhdrc` to set `YNY_WARM_HELPER_SOCKET=/tmp/yny-warm.sock`.

**Tech Stack:** Nix, nix-darwin `launchd.user.agents`, `skhd`, local `yny` release binary, macOS `launchctl`, Unix domain sockets.

---

### Task 1: Add the launchd warm-helper agent

**Files:**
- Modify: `den/aspects/features/darwin-desktop.nix`
- Read: `den/aspects/features/darwin-core.nix`
- Read: `docs/plans/2026-03-31-yny-warm-helper-design.md`

**Step 1: Build the current Darwin system closure as a baseline**

Run:

```bash
cd ~/.config/nix && WRAPPER=$(bash scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file --max-jobs 8 --cores 0
```

Expected: PASS. This proves the current desktop config evaluates cleanly before editing.

**Step 2: Add the `launchd.user.agents.yny-warm-helper` block next to the existing desktop agents**

```nix
launchd.user.agents.yny-warm-helper = {
  serviceConfig = {
    ProgramArguments = [
      "/Users/m/.cargo/target/release/yny"
      "--config"
      "/Users/m/yny.config.dev.toml"
      "warm-helper"
      "serve"
      "--socket"
      "/tmp/yny-warm.sock"
    ];
    RunAtLoad = true;
    KeepAlive = true;
    LimitLoadToSessionType = "Aqua";
    ProcessType = "Interactive";
    StandardOutPath = "/tmp/yny-warm-helper.log";
    StandardErrorPath = "/tmp/yny-warm-helper.log";
  };
};
```

Keep the service in `darwin-desktop.nix`, not `darwin-core.nix`, because it is coupled to the local desktop hotkey setup.

**Step 3: Rebuild the Darwin system closure to catch syntax or evaluation mistakes**

Run the same command from Step 1.

Expected: PASS. If it fails, fix the attribute nesting or `ProgramArguments` shape before moving on.

**Step 4: Commit the launchd service change**

```bash
git add den/aspects/features/darwin-desktop.nix
git commit -m $'feat: add yny warm helper launchd agent\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 2: Route only focus bindings through the helper

**Files:**
- Modify: `dotfiles/by-host/darwin/skhdrc`
- Read: `docs/plans/2026-03-31-yny-warm-helper-design.md`

**Step 1: Update only the four `focus` commands to inject the helper socket**

Each focus binding should keep the current binary path, log flags, profiling flag, and config path, but add the socket env var in front of the command:

```sh
/usr/bin/env YNY_WARM_HELPER_SOCKET=/tmp/yny-warm.sock /Users/m/.cargo/target/release/yny --log-file=/tmp/yny/debug.log --profile --log-append --config /Users/m/yny.config.dev.toml focus west
```

Apply the same pattern to the south, north, and east focus bindings.

**Step 2: Leave all four `move` bindings unchanged**

Run:

```bash
git --no-pager diff -- dotfiles/by-host/darwin/skhdrc
```

Expected: the diff changes only the four `focus` lines. The `move` lines should stay byte-for-byte the same.

**Step 3: Rebuild the Darwin system closure again**

Run:

```bash
cd ~/.config/nix && WRAPPER=$(bash scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file --max-jobs 8 --cores 0
```

Expected: PASS. This catches any `skhd` config embedding or Nix evaluation regressions before applying the system.

**Step 4: Commit the `skhd` binding change**

```bash
git add dotfiles/by-host/darwin/skhdrc
git commit -m $'feat: route skhd focus through yny warm helper\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

### Task 3: Apply the config and verify the helper is live

**Files:**
- Read: `den/aspects/features/darwin-desktop.nix`
- Read: `dotfiles/by-host/darwin/skhdrc`
- Read: `/tmp/yny-warm-helper.log`
- Read: `/tmp/yny/debug.log`

**Step 1: Apply the updated Darwin system**

Run:

```bash
cd ~/.config/nix && WRAPPER=$(bash scripts/external-input-flake.sh) && NIXPKGS_ALLOW_UNFREE=1 nix build --extra-experimental-features 'nix-command flakes' "path:$WRAPPER#darwinConfigurations.macbook-pro-m1.system" --no-write-lock-file --max-jobs 8 --cores 0 && sudo NIXPKGS_ALLOW_UNFREE=1 ./result/sw/bin/darwin-rebuild switch --flake "path:$WRAPPER#macbook-pro-m1" --no-write-lock-file
```

Expected: PASS. The updated `launchd` service and `skhd` config are installed.

**Step 2: Confirm the helper agent and socket exist**

Run:

```bash
launchctl print gui/$(id -u) | rg "yny-warm-helper"
ls -l /tmp/yny-warm.sock /tmp/yny-warm-helper.log
```

Expected: the launchd printout contains `yny-warm-helper`, the socket exists, and the log file exists.

**Step 3: Smoke-test helper-backed focus directly**

Run:

```bash
YNY_WARM_HELPER_SOCKET=/tmp/yny-warm.sock /Users/m/.cargo/target/release/yny --log-file=/tmp/yny/debug.log --profile --log-append --config /Users/m/yny.config.dev.toml focus west
YNY_WARM_HELPER_SOCKET=/tmp/yny-warm.sock /Users/m/.cargo/target/release/yny --log-file=/tmp/yny/debug.log --profile --log-append --config /Users/m/yny.config.dev.toml focus east
```

Expected: both commands reach the helper path and behave the same way as the new hotkeys.

**Step 4: Test the real hotkeys and confirm `move` still stays daemonless**

- Press the four focus hotkeys (`ctrl-n`, `ctrl-e`, `ctrl-i`, `ctrl-o`) in normal desktop apps.
- Press at least one move hotkey afterward.

Expected: focus hotkeys work through the helper, and move hotkeys still behave exactly as before.

**Step 5: Inspect logs after the smoke test**

Run:

```bash
tail -n 50 /tmp/yny-warm-helper.log
tail -n 50 /tmp/yny/debug.log
```

Expected: the helper log shows served focus requests, and the main debug log still records the normal command activity.
