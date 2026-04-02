# Zellij Plugin Removal Design

## Problem

`yeetnyoink` currently depends on a custom Zellij plugin (`plugins/zellij-bridge`) for pane and tab moves that should be exposed as public CLI actions instead.

The active goal is to replace that plugin with a small upstreamable four-patch series:

- `move-pane-to-tab`
- session transfer groundwork
- `move-pane-to-session`
- `move-tab-to-session`

For the cross-session commands, the destination must receive the live pane/tab state rather than a recreated layout or respawned command.

## Goals

- Remove the need for the custom `zellij-bridge` plugin in the `yeetnyoink` flow
- Keep the public CLI surface coherent and script-friendly
- Preserve live pane/tab state for cross-session moves
- Split the work into reviewable patches
- Keep the result upstreamable, with targeted tests and docs per patch

## Non-goals

- No new plugin / pipe control API
- No new permission model
- No new pane-query command in this change
- No recreate-from-layout fallback for the cross-session commands
- No silent compatibility layer or heuristic guessing

## Approved design

### Patch 1: `zellij action move-pane-to-tab`

Expose a documented public CLI action for moving a pane into another tab.

- `zellij action move-pane-to-tab --new-tab [--name <TAB_NAME>] [--pane-id <PANE_ID>]`
- `zellij action move-pane-to-tab --tab-id <TAB_ID> [--pane-id <PANE_ID>]`

Semantics:

- `--new-tab` moves the pane into a freshly created tab
- `--tab-id` moves the pane into an existing tab by stable ID
- `--pane-id` remains optional; omitted means the focused pane
- focus should follow the moved pane into the destination tab

Implementation should reuse the existing same-session pane extraction / move path and carry forward the runtime fixes needed for detached CLI usage and protobuf decode.

### Patch 2: session transfer groundwork

Add the minimum internal server-side plumbing needed to move live panes between sessions without a plugin.

Semantics:

- no new public user-facing command in this patch
- introduce the Unix-only transfer mechanism used by the later session-moving commands
- keep the groundwork narrow: socket setup, request/response framing, FD passing, PTY adoption, and the supporting tests

### Patch 3: `zellij action move-pane-to-session`

Add a public CLI action for transferring a pane into another session.

- `zellij action move-pane-to-session --new-session [--pane-id <PANE_ID>]`
- `zellij action move-pane-to-session --session-name <SESSION_NAME> --tab-id <TAB_ID> [--pane-id <PANE_ID>]`

Semantics:

- true live transfer of the selected pane into another session
- no respawn / no layout recreation fallback
- source session loses the pane
- destination session gains the live pane in the requested target tab, or in a newly created destination session when `--new-session` is used

### Patch 4: `zellij action move-tab-to-session`

Add a public CLI action for transferring the active tab into another session.

- `zellij action move-tab-to-session --new-session`
- `zellij action move-tab-to-session --session-name <SESSION_NAME>`

Semantics:

- true live transfer of the active tab into another session
- all panes in the tab move with their live state intact
- source session loses the tab
- destination session gains the transferred tab

## Architecture findings

The old assumption that session-moving commands could piggyback on session-switch or layout replay is not valid for the live-transfer semantics.

Important findings from the upstream checkout:

- each named Zellij session uses its own server daemon and IPC socket
- each server instance owns a single `SessionMetaData`
- `ServerInstruction::SwitchSession` only tells a client to disconnect and reconnect; it does not transfer pane or tab state

Implication:

- patch 1 stays relatively small and can reuse existing screen logic
- patches 2 through 4 require a real cross-session transfer mechanism, likely spanning server routing, PTY ownership/lifecycle, and destination-session insertion

## Testing strategy

Follow strict TDD:

1. write a failing test first
2. verify the failure is for the intended missing behavior
3. write the minimum code to make it pass
4. keep the patch split reviewable

Primary test locations:

- `zellij-utils/src/cli.rs` for CLI parsing/help coverage
- `zellij-utils/src/input/actions.rs` for `CliAction` -> `Action` conversion
- `zellij-server/src/route.rs` for action-to-instruction routing
- `zellij-server/src/unit/screen_tests.rs` for same-session movement behavior
- additional server/session integration tests for true cross-session transfer

## Planned patch split

1. `zellij-0001-add-move-pane-to-tab-cli.patch`
2. `zellij-0002-add-session-transfer-groundwork.patch`
3. `zellij-0003-add-move-pane-to-session-cli.patch`
4. `zellij-0004-add-move-tab-to-session-cli.patch`
