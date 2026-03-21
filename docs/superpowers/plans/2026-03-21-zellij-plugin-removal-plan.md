# Zellij Plugin Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce two upstream-ready Zellij patch files in `/nixos-config/patches` that expose public CLI actions for breaking a pane into a new tab and moving a pane into an existing tab, so `yeetnyoink` no longer needs its custom Zellij plugin.

**Architecture:** Treat this repo as the artifact host and a temporary upstream checkout as the implementation workspace. Implement the two CLI features as separate, minimal Rust changes on top of Zellij’s existing screen/server machinery, verify each feature with targeted upstream tests plus manpage regeneration, then export each logical change as its own plain unified diff patch into `/nixos-config/patches`.

**Tech Stack:** Rust, Clap 3, Zellij workspace (`zellij-utils`, `zellij-server`), Cargo, `cargo xtask`, unified diff patch files

---

## File structure

- Reference: `docs/superpowers/spec/2026-03-21-zellij-plugin-removal-design.md`
- Create: `docs/superpowers/plans/2026-03-21-zellij-plugin-removal-plan.md`
- Create: `patches/0001-zellij-expose-break-pane-cli.patch`
- Create: `patches/0002-zellij-add-move-pane-to-tab-cli.patch`
- Temporary workspace: `/tmp/zellij-upstream/`
- Modify in temporary workspace:
  - `/tmp/zellij-upstream/zellij-utils/src/cli.rs`
  - `/tmp/zellij-upstream/zellij-utils/src/input/actions.rs`
  - `/tmp/zellij-upstream/zellij-server/src/route.rs`
  - `/tmp/zellij-upstream/zellij-server/src/screen.rs`
  - `/tmp/zellij-upstream/zellij-server/src/unit/screen_tests.rs`
  - `/tmp/zellij-upstream/docs/MANPAGE.md`
  - `/tmp/zellij-upstream/assets/man/zellij.1` (generated via `cargo xtask manpage`)

## Task 1: Prepare the upstream scratch tree

**Files:**
- Create: `/tmp/zellij-upstream/`
- Reference: `/nixos-config/docs/superpowers/spec/2026-03-21-zellij-plugin-removal-design.md`
- Verify: `/tmp/zellij-upstream/zellij-utils/src/cli.rs`
- Verify: `/tmp/zellij-upstream/zellij-utils/src/input/actions.rs`
- Verify: `/tmp/zellij-upstream/zellij-server/src/route.rs`
- Verify: `/tmp/zellij-upstream/zellij-server/src/screen.rs`
- Verify: `/tmp/zellij-upstream/zellij-server/src/unit/screen_tests.rs`

- [ ] **Step 1: Materialize a clean upstream checkout**

Run:

```bash
gh repo clone zellij-org/zellij /tmp/zellij-upstream
git -C /tmp/zellij-upstream checkout main
git -C /tmp/zellij-upstream switch -c copilot/zellij-plugin-removal
```

Expected: `/tmp/zellij-upstream` exists, points at upstream `main`, and has a clean work branch.

- [ ] **Step 2: Confirm the implementation touchpoints exist before changing anything**

Run:

```bash
rg -n "BreakPane|BreakPanesToNewTab|BreakPanesToTabWithId" \
  /tmp/zellij-upstream/zellij-utils/src/input/actions.rs \
  /tmp/zellij-upstream/zellij-server/src/route.rs \
  /tmp/zellij-upstream/zellij-server/src/screen.rs
```

Expected: matches in `actions.rs`, `route.rs`, and `screen.rs`, confirming the plan is still aligned with upstream.

- [ ] **Step 3: Run a narrow baseline test set**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils subscribe_scrollback_bare_flag --lib
cargo test -p zellij-utils test_send_keys_single_key --lib
cargo test -p zellij-server send_cli_go_to_tab_by_id_action --lib
```

Expected: all three tests pass before feature work starts.

## Task 2: Add `break-pane` CLI parsing and CLI-to-action mapping

**Files:**
- Modify: `/tmp/zellij-upstream/zellij-utils/src/cli.rs`
- Modify: `/tmp/zellij-upstream/zellij-utils/src/input/actions.rs`
- Test: `/tmp/zellij-upstream/zellij-utils/src/cli.rs`
- Test: `/tmp/zellij-upstream/zellij-utils/src/input/actions.rs`

- [ ] **Step 1: Add a failing CLI parser test for `break-pane`**

Add these tests to `zellij-utils/src/cli.rs`:

```rust
#[test]
fn break_pane_parses_optional_pane_id_and_name() {
    let cli = CliArgs::try_parse_from([
        "zellij",
        "action",
        "break-pane",
        "--pane-id",
        "terminal_7",
        "--name",
        "scratch",
    ])
    .unwrap();

    match cli.command {
        Some(Command::Action(action)) => match *action {
            CliAction::BreakPane { pane_id, name } => {
                assert_eq!(pane_id, Some("terminal_7".to_string()));
                assert_eq!(name, Some("scratch".to_string()));
            },
            other => panic!("expected BreakPane, got {other:?}"),
        },
        other => panic!("expected action command, got {other:?}"),
    }
}

#[test]
fn break_pane_parses_without_flags() {
    let cli = CliArgs::try_parse_from(["zellij", "action", "break-pane"]).unwrap();

    match cli.command {
        Some(Command::Action(action)) => match *action {
            CliAction::BreakPane { pane_id, name } => {
                assert_eq!(pane_id, None);
                assert_eq!(name, None);
            },
            other => panic!("expected BreakPane, got {other:?}"),
        },
        other => panic!("expected action command, got {other:?}"),
    }
}

#[test]
fn break_pane_allows_omitting_pane_id() {
    let cli = CliArgs::try_parse_from(["zellij", "action", "break-pane", "--name", "scratch"])
        .unwrap();

    match cli.command {
        Some(Command::Action(action)) => match *action {
            CliAction::BreakPane { pane_id, name } => {
                assert_eq!(pane_id, None);
                assert_eq!(name, Some("scratch".to_string()));
            },
            other => panic!("expected BreakPane, got {other:?}"),
        },
        other => panic!("expected action command, got {other:?}"),
    }
}
```

- [ ] **Step 2: Run the parser test to prove it fails first**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils break_pane_parses_optional_pane_id_and_name --lib
cargo test -p zellij-utils break_pane_parses_without_flags --lib
cargo test -p zellij-utils break_pane_allows_omitting_pane_id --lib
```

Expected: all three tests FAIL because `CliAction::BreakPane` does not exist yet.

- [ ] **Step 3: Add the new CLI action variant**

Add a new subcommand variant in `zellij-utils/src/cli.rs`:

```rust
/// Break a pane into a new tab
BreakPane {
    /// Target a specific pane by ID (eg. terminal_1, plugin_2, or 3)
    #[clap(long, value_parser)]
    pane_id: Option<String>,
    /// Name of the newly created tab
    #[clap(long, value_parser)]
    name: Option<String>,
},
```

- [ ] **Step 4: Add failing action-mapping tests**

Add these tests to `zellij-utils/src/input/actions.rs`:

```rust
#[test]
fn test_break_pane_cli_action_with_target_and_name() {
    let cli_action = CliAction::BreakPane {
        pane_id: Some("terminal_7".to_string()),
        name: Some("scratch".to_string()),
    };

    let actions =
        Action::actions_from_cli(cli_action, Box::new(|| PathBuf::from("/tmp")), None).unwrap();

    assert_eq!(
        actions,
        vec![Action::BreakPaneToNewTab {
            pane_id: Some(PaneId::Terminal(7)),
            tab_name: Some("scratch".to_string()),
        }]
    );
}

#[test]
fn test_break_pane_cli_action_without_target_uses_focused_pane() {
    let cli_action = CliAction::BreakPane {
        pane_id: None,
        name: Some("scratch".to_string()),
    };

    let actions =
        Action::actions_from_cli(cli_action, Box::new(|| PathBuf::from("/tmp")), None).unwrap();

    assert_eq!(
        actions,
        vec![Action::BreakPaneToNewTab {
            pane_id: None,
            tab_name: Some("scratch".to_string()),
        }]
    );
}
```

- [ ] **Step 5: Run the action-mapping test to prove it fails**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils test_break_pane_cli_action_with_target_and_name --lib
cargo test -p zellij-utils test_break_pane_cli_action_without_target_uses_focused_pane --lib
```

Expected: both tests FAIL because `Action::BreakPaneToNewTab` does not exist yet.

- [ ] **Step 6: Add the internal action and CLI mapping**

Extend `zellij-utils/src/input/actions.rs` with a dedicated action:

```rust
BreakPaneToNewTab {
    pane_id: Option<PaneId>,
    tab_name: Option<String>,
},
```

Map the CLI action to it:

```rust
CliAction::BreakPane { pane_id, name } => Ok(vec![Action::BreakPaneToNewTab {
    pane_id: pane_id
        .as_deref()
        .map(actions::parse_pane_id)
        .transpose()?,
    tab_name: name,
}]),
```

- [ ] **Step 7: Re-run the focused `zellij-utils` tests**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils break_pane_parses_optional_pane_id_and_name --lib
cargo test -p zellij-utils break_pane_parses_without_flags --lib
cargo test -p zellij-utils break_pane_allows_omitting_pane_id --lib
cargo test -p zellij-utils test_break_pane_cli_action_with_target_and_name --lib
cargo test -p zellij-utils test_break_pane_cli_action_without_target_uses_focused_pane --lib
```

Expected: all five tests PASS.

## Task 3: Add `break-pane` screen plumbing, docs, and export patch 1

**Files:**
- Modify: `/tmp/zellij-upstream/zellij-server/src/route.rs`
- Modify: `/tmp/zellij-upstream/zellij-server/src/screen.rs`
- Modify: `/tmp/zellij-upstream/zellij-server/src/unit/screen_tests.rs`
- Modify: `/tmp/zellij-upstream/docs/MANPAGE.md`
- Modify: `/tmp/zellij-upstream/assets/man/zellij.1`
- Create: `/nixos-config/patches/0001-zellij-expose-break-pane-cli.patch`

- [ ] **Step 1: Add a failing screen-level test for the focused-pane default**

Add this test to `zellij-server/src/unit/screen_tests.rs`:

```rust
#[test]
pub fn break_pane_without_pane_id_uses_the_invoking_clients_focused_pane() {
    // Use the same mock-screen/session bootstrap pattern as send_cli_go_to_tab_by_id_action()
    // and the same breakable-pane fixture shape as screen_can_break_pane_to_a_new_tab().
    // Record the invoking client's focused pane ID before dispatch.
    // Send CliAction::BreakPane { pane_id: None, name: Some("scratch".into()) }.
    // Assert that:
    // 1. the source tab no longer contains the recorded pane ID
    // 2. a newly created tab named "scratch" contains that pane ID
    // 3. the invoking client now focuses the new tab
    // 4. the action still triggers screen renders
}
```

Keep the structure parallel to `send_cli_go_to_tab_by_id_action` so the new test fits existing patterns.

- [ ] **Step 2: Run the new screen test to prove it fails**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-server break_pane_without_pane_id_uses_the_invoking_clients_focused_pane --lib
```

Expected: FAIL because route/screen plumbing for the CLI action does not exist yet.

- [ ] **Step 3: Add a dedicated screen instruction that can resolve the focused pane when `--pane-id` is omitted**

Add a new instruction in `zellij-server/src/screen.rs`:

```rust
BreakPaneToNewTab {
    pane_id: Option<PaneId>,
    new_tab_name: Option<String>,
    client_id: ClientId,
    completion_tx: Option<NotificationEnd>,
},
```

Handle it by resolving `pane_id` from `screen.get_active_pane_id(&client_id)` when needed and then forwarding to the existing `break_multiple_panes_to_new_tab(...)` path with `should_change_focus_to_new_tab = true`.

- [ ] **Step 4: Route the new internal action into the new screen instruction**

Add this route branch in `zellij-server/src/route.rs`:

```rust
Action::BreakPaneToNewTab { pane_id, tab_name } => {
    senders
        .send_to_screen(ScreenInstruction::BreakPaneToNewTab {
            pane_id,
            new_tab_name: tab_name,
            client_id,
            completion_tx: Some(NotificationEnd::new(completion_tx)),
        })
        .with_context(err_context)?;
},
```

- [ ] **Step 5: Document the new user-facing action**

Add a concise entry to `/tmp/zellij-upstream/docs/MANPAGE.md`:

```md
* __BreakPane: [--pane-id <ID>] [--name <NAME>]__ - breaks a pane into a new tab.
  If `--pane-id` is omitted, breaks the focused pane for the invoking client.
  If `--name` is provided, names the new tab.
```

- [ ] **Step 6: Regenerate the packaged manpage**

Run:

```bash
cd /tmp/zellij-upstream
cargo xtask manpage
```

Expected: `assets/man/zellij.1` changes to match `docs/MANPAGE.md`.

- [ ] **Step 7: Run the targeted verification for patch 1**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils break_pane --lib
cargo test -p zellij-server break_pane_without_pane_id_uses_the_invoking_clients_focused_pane --lib
cargo test -p zellij-server screen_can_break_pane_to_a_new_tab --lib
```

Expected: all targeted tests PASS.

- [ ] **Step 8: Commit the upstream scratch-tree change for patch 1**

Run:

```bash
cd /tmp/zellij-upstream
git add zellij-utils/src/cli.rs \
        zellij-utils/src/input/actions.rs \
        zellij-server/src/route.rs \
        zellij-server/src/screen.rs \
        zellij-server/src/unit/screen_tests.rs \
        docs/MANPAGE.md \
        assets/man/zellij.1
git commit -m "feat: expose break-pane cli"
```

Expected: one upstream-local commit containing only patch-1 behavior.

- [ ] **Step 9: Export patch 1 into this repo**

Run:

```bash
git -C /tmp/zellij-upstream show --format= --binary --full-index HEAD \
  > /nixos-config/patches/0001-zellij-expose-break-pane-cli.patch
```

Expected: `/nixos-config/patches/0001-zellij-expose-break-pane-cli.patch` exists and contains a plain unified diff.

- [ ] **Step 10: Commit the repo artifact for patch 1**

Run:

```bash
cd /nixos-config
git add docs/superpowers/spec/2026-03-21-zellij-plugin-removal-design.md \
        docs/superpowers/plans/2026-03-21-zellij-plugin-removal-plan.md \
        patches/0001-zellij-expose-break-pane-cli.patch
git commit -m "feat: add zellij break-pane patch"
```

Expected: one repo commit records the approved spec/plan plus patch 1 artifact.

## Task 4: Add `move-pane-to-tab` CLI parsing and CLI-to-action mapping

**Files:**
- Modify: `/tmp/zellij-upstream/zellij-utils/src/cli.rs`
- Modify: `/tmp/zellij-upstream/zellij-utils/src/input/actions.rs`
- Test: `/tmp/zellij-upstream/zellij-utils/src/cli.rs`
- Test: `/tmp/zellij-upstream/zellij-utils/src/input/actions.rs`

- [ ] **Step 1: Add a failing CLI parser test for `move-pane-to-tab`**

Add these tests to `zellij-utils/src/cli.rs`:

```rust
#[test]
fn move_pane_to_tab_parses_tab_id_and_optional_pane_id() {
    let cli = CliArgs::try_parse_from([
        "zellij",
        "action",
        "move-pane-to-tab",
        "--tab-id",
        "42",
        "--pane-id",
        "terminal_7",
    ])
    .unwrap();

    match cli.command {
        Some(Command::Action(action)) => match *action {
            CliAction::MovePaneToTab { tab_id, pane_id } => {
                assert_eq!(tab_id, 42);
                assert_eq!(pane_id, Some("terminal_7".to_string()));
            },
            other => panic!("expected MovePaneToTab, got {other:?}"),
        },
        other => panic!("expected action command, got {other:?}"),
    }
}

#[test]
fn move_pane_to_tab_requires_tab_id() {
    let result = CliArgs::try_parse_from(["zellij", "action", "move-pane-to-tab"]);
    assert!(result.is_err());
}

#[test]
fn move_pane_to_tab_allows_omitting_pane_id() {
    let cli = CliArgs::try_parse_from([
        "zellij",
        "action",
        "move-pane-to-tab",
        "--tab-id",
        "42",
    ])
    .unwrap();

    match cli.command {
        Some(Command::Action(action)) => match *action {
            CliAction::MovePaneToTab { tab_id, pane_id } => {
                assert_eq!(tab_id, 42);
                assert_eq!(pane_id, None);
            },
            other => panic!("expected MovePaneToTab, got {other:?}"),
        },
        other => panic!("expected action command, got {other:?}"),
    }
}
```

- [ ] **Step 2: Run the parser test to prove it fails**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils move_pane_to_tab_parses_tab_id_and_optional_pane_id --lib
cargo test -p zellij-utils move_pane_to_tab_requires_tab_id --lib
cargo test -p zellij-utils move_pane_to_tab_allows_omitting_pane_id --lib
```

Expected: the positive parse tests FAIL because `CliAction::MovePaneToTab` does not exist yet, and the required-flag test also fails until the subcommand exists with the correct clap contract.

- [ ] **Step 3: Add the new CLI action variant**

Add this variant in `zellij-utils/src/cli.rs`:

```rust
/// Move a pane into an existing tab by stable tab ID
MovePaneToTab {
    #[clap(long, value_parser)]
    tab_id: u64,
    #[clap(long, value_parser)]
    pane_id: Option<String>,
},
```

- [ ] **Step 4: Add failing action-mapping tests**

Add these tests to `zellij-utils/src/input/actions.rs`:

```rust
#[test]
fn test_move_pane_to_tab_cli_action() {
    let cli_action = CliAction::MovePaneToTab {
        tab_id: 42,
        pane_id: Some("terminal_7".to_string()),
    };

    let actions =
        Action::actions_from_cli(cli_action, Box::new(|| PathBuf::from("/tmp")), None).unwrap();

    assert_eq!(
        actions,
        vec![Action::MovePaneToTab {
            pane_id: Some(PaneId::Terminal(7)),
            tab_id: 42,
        }]
    );
}

#[test]
fn test_move_pane_to_tab_cli_action_without_target() {
    let cli_action = CliAction::MovePaneToTab {
        tab_id: 42,
        pane_id: None,
    };

    let actions =
        Action::actions_from_cli(cli_action, Box::new(|| PathBuf::from("/tmp")), None).unwrap();

    assert_eq!(
        actions,
        vec![Action::MovePaneToTab {
            pane_id: None,
            tab_id: 42,
        }]
    );
}
```

- [ ] **Step 5: Run the action-mapping test to prove it fails**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils test_move_pane_to_tab_cli_action --lib
cargo test -p zellij-utils test_move_pane_to_tab_cli_action_without_target --lib
```

Expected: both tests FAIL because `Action::MovePaneToTab` does not exist yet.

- [ ] **Step 6: Add the internal action and CLI mapping**

Extend `zellij-utils/src/input/actions.rs` with:

```rust
MovePaneToTab {
    pane_id: Option<PaneId>,
    tab_id: u64,
},
```

Map the CLI action:

```rust
CliAction::MovePaneToTab { tab_id, pane_id } => Ok(vec![Action::MovePaneToTab {
    pane_id: pane_id
        .as_deref()
        .map(actions::parse_pane_id)
        .transpose()?,
    tab_id,
}]),
```

- [ ] **Step 7: Re-run the focused `zellij-utils` tests**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils move_pane_to_tab_parses_tab_id_and_optional_pane_id --lib
cargo test -p zellij-utils move_pane_to_tab_requires_tab_id --lib
cargo test -p zellij-utils move_pane_to_tab_allows_omitting_pane_id --lib
cargo test -p zellij-utils test_move_pane_to_tab_cli_action --lib
cargo test -p zellij-utils test_move_pane_to_tab_cli_action_without_target --lib
```

Expected: all five tests PASS.

## Task 5: Add `move-pane-to-tab` screen plumbing, docs, and export patch 2

**Files:**
- Modify: `/tmp/zellij-upstream/zellij-server/src/route.rs`
- Modify: `/tmp/zellij-upstream/zellij-server/src/screen.rs`
- Modify: `/tmp/zellij-upstream/zellij-server/src/unit/screen_tests.rs`
- Modify: `/tmp/zellij-upstream/docs/MANPAGE.md`
- Modify: `/tmp/zellij-upstream/assets/man/zellij.1`
- Create: `/nixos-config/patches/0002-zellij-add-move-pane-to-tab-cli.patch`

- [ ] **Step 1: Add a failing screen-level test for `move-pane-to-tab`**

Add this test to `zellij-server/src/unit/screen_tests.rs`:

```rust
#[test]
pub fn move_pane_to_tab_without_pane_id_uses_focused_pane_stable_tab_id_and_target_focus() {
    // Start from the same mock-screen/session bootstrap as send_cli_go_to_tab_by_id_action().
    // Reorder or otherwise shape the tabs so the target tab's stable ID differs from its position.
    // Record the invoking client's focused pane ID in the source tab and record the target tab's stable ID.
    // Send CliAction::MovePaneToTab { tab_id: <stable id>, pane_id: None }.
    // Assert that:
    // 1. the source tab no longer contains the recorded pane ID
    // 2. the tab with the recorded stable ID now contains that pane ID
    // 3. the move did not accidentally target the tab merely occupying that position
    // 4. the invoking client now focuses the target tab
    // 5. the action still triggers screen renders
}
```

- [ ] **Step 2: Run the new screen test to prove it fails**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-server move_pane_to_tab_without_pane_id_uses_focused_pane_stable_tab_id_and_target_focus --lib
```

Expected: FAIL because route/screen plumbing for the CLI action does not exist yet.

- [ ] **Step 3: Add a screen instruction that can resolve the focused pane when `--pane-id` is omitted and still target a stable tab ID**

Add a new instruction in `zellij-server/src/screen.rs`:

```rust
MovePaneToTabById {
    pane_id: Option<PaneId>,
    tab_id: usize,
    client_id: ClientId,
    completion_tx: Option<NotificationEnd>,
},
```

Handle it by:

```rust
let pane_id = pane_id
    .or_else(|| screen.get_active_pane_id(&client_id))
    .ok_or_else(|| anyhow!("No active pane found for client {:?}", client_id))?;

let tab_position = screen
    .get_tab_position_by_id(tab_id)
    .ok_or_else(|| anyhow!("Tab with ID {} not found", tab_id))?;

screen.break_multiple_panes_to_tab_with_index(vec![pane_id], tab_position, true, client_id)?;
```

Keep this logic self-contained inside `MovePaneToTabById`; do not expand the change by refactoring unrelated existing handlers.

- [ ] **Step 4: Route the new internal action into the new screen instruction**

Add this route branch in `zellij-server/src/route.rs`:

```rust
Action::MovePaneToTab { pane_id, tab_id } => {
    let tab_id = usize::try_from(tab_id).with_context(|| "tab id does not fit in usize")?;
    senders
        .send_to_screen(ScreenInstruction::MovePaneToTabById {
            pane_id,
            tab_id,
            client_id,
            completion_tx: Some(NotificationEnd::new(completion_tx)),
        })
        .with_context(err_context)?;
},
```

- [ ] **Step 5: Document the new user-facing action**

Add this entry to `/tmp/zellij-upstream/docs/MANPAGE.md`:

```md
* __MovePaneToTab: --tab-id <TAB_ID> [--pane-id <ID>]__ - moves a pane into an existing tab by stable tab ID.
  If `--pane-id` is omitted, moves the focused pane for the invoking client.
```

- [ ] **Step 6: Regenerate the packaged manpage**

Run:

```bash
cd /tmp/zellij-upstream
cargo xtask manpage
```

Expected: `assets/man/zellij.1` updates again to include the new action.

- [ ] **Step 7: Run the targeted verification for patch 2**

Run:

```bash
cd /tmp/zellij-upstream
cargo test -p zellij-utils move_pane_to_tab --lib
cargo test -p zellij-server move_pane_to_tab_without_pane_id_uses_focused_pane_stable_tab_id_and_target_focus --lib
cargo test -p zellij-server send_cli_go_to_tab_by_id_action --lib
```

Expected: all targeted tests PASS.

- [ ] **Step 8: Commit the upstream scratch-tree change for patch 2**

Run:

```bash
cd /tmp/zellij-upstream
git add zellij-utils/src/cli.rs \
        zellij-utils/src/input/actions.rs \
        zellij-server/src/route.rs \
        zellij-server/src/screen.rs \
        zellij-server/src/unit/screen_tests.rs \
        docs/MANPAGE.md \
        assets/man/zellij.1
git commit -m "feat: add move-pane-to-tab cli"
```

Expected: one upstream-local commit containing only patch-2 behavior.

- [ ] **Step 9: Export patch 2 into this repo**

Run:

```bash
git -C /tmp/zellij-upstream show --format= --binary --full-index HEAD \
  > /nixos-config/patches/0002-zellij-add-move-pane-to-tab-cli.patch
```

Expected: `/nixos-config/patches/0002-zellij-add-move-pane-to-tab-cli.patch` exists and contains only the second logical patch.

- [ ] **Step 10: Commit the repo artifact for patch 2**

Run:

```bash
cd /nixos-config
git add patches/0002-zellij-add-move-pane-to-tab-cli.patch
git commit -m "feat: add zellij move-pane-to-tab patch"
```

Expected: the repo now records the second patch artifact in its own commit.

## Task 6: Validate the patch series from the repo artifacts

**Files:**
- Verify: `/nixos-config/patches/0001-zellij-expose-break-pane-cli.patch`
- Verify: `/nixos-config/patches/0002-zellij-add-move-pane-to-tab-cli.patch`
- Verify: `/tmp/zellij-upstream/`

- [ ] **Step 1: Create a fresh verification checkout**

Run:

```bash
rm -rf /tmp/zellij-upstream-verify
gh repo clone zellij-org/zellij /tmp/zellij-upstream-verify
git -C /tmp/zellij-upstream-verify checkout main
```

Expected: a clean second checkout exists for dry-run application.

- [ ] **Step 2: Verify that patch 1 applies cleanly**

Run:

```bash
cd /tmp/zellij-upstream-verify
git apply --check /nixos-config/patches/0001-zellij-expose-break-pane-cli.patch
```

Expected: no output and exit code 0.

- [ ] **Step 3: Verify that patch 2 applies after patch 1**

Run:

```bash
cd /tmp/zellij-upstream-verify
git apply /nixos-config/patches/0001-zellij-expose-break-pane-cli.patch
git apply --check /nixos-config/patches/0002-zellij-add-move-pane-to-tab-cli.patch
```

Expected: patch 2 also applies cleanly on top of patch 1.

- [ ] **Step 4: Apply the full series and run final targeted upstream verification**

Run:

```bash
cd /tmp/zellij-upstream-verify
git apply /nixos-config/patches/0002-zellij-add-move-pane-to-tab-cli.patch
cargo test -p zellij-utils break_pane --lib
cargo test -p zellij-utils move_pane_to_tab --lib
cargo test -p zellij-server break_pane_without_pane_id_uses_the_invoking_clients_focused_pane --lib
cargo test -p zellij-server screen_can_break_pane_to_a_new_tab --lib
cargo test -p zellij-server move_pane_to_tab_without_pane_id_uses_focused_pane_stable_tab_id_and_target_focus --lib
cargo xtask manpage
git diff --exit-code -- assets/man/zellij.1
```

Expected: all targeted tests pass, the manpage regenerates successfully, and rerunning `cargo xtask manpage` leaves `assets/man/zellij.1` unchanged.

- [ ] **Step 5: Run final repo hygiene checks**

Run:

```bash
cd /nixos-config
git diff --check
```

Expected: no whitespace or patch-formatting errors.
