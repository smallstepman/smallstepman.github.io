# Zellij plugin-removal design

## Problem

`yeetnyoink` currently depends on a custom Zellij plugin (`plugins/zellij-bridge`) to:

- break a pane into a new tab
- move a pane into an existing tab
- avoid inventing a plugin-only control path for functionality Zellij already largely has internally

The goal is to prepare a small upstreamable Zellij patch set that lets `yeetnyoink` drop that plugin entirely while still reading as a generally useful scripting feature for Zellij users.

## Goals

- Remove the need for a custom Zellij plugin in the `yeetnyoink` flow
- Keep the public API surface minimal and script-friendly
- Reuse existing Zellij internals where possible
- Make the resulting feature obviously useful beyond `yeetnyoink`

## Non-goals

- No new plugin / pipe control API
- No new permission model
- No new pane-query command in this change
- No broad redesign of Zellij scripting or tab management

## Approved design

### Patch 1: expose `zellij action break-pane`

Make `break-pane` a documented public CLI action.

- Default behavior: break the focused pane into a new tab
- Optional `--pane-id <PANE_ID>`: target a specific pane instead of the focused pane
- Optional `--name <TAB_NAME>`: set the new tab name
- Focus behavior: the invoking client follows the pane into the new tab

Implementation should reuse Zellij's existing break-to-new-tab path rather than adding a new plugin-like control flow.

### Patch 2: add `zellij action move-pane-to-tab`

Add a second documented public CLI action for moving a pane into an existing tab.

- Required `--tab-id <TAB_ID>`: stable target tab identifier
- Optional `--pane-id <PANE_ID>`: target a specific pane instead of the focused pane
- Focus behavior: the invoking client focuses the target tab after the move, while otherwise inheriting Zellij's existing break-to-tab semantics rather than adding custom pane-focus rules

Implementation should reuse the existing screen/server path that already moves panes into a tab by stable ID.

### Introspection strategy

Do not add a new pane-info command in this patch set.

Scripting and downstream consumers should rely on already-existing discovery commands:

- `zellij action list-clients`
- `zellij action list-panes`
- `zellij action list-tabs`
- `zellij action current-tab-info`

These commands already exist on current upstream `main`, so this patch set does not need a companion introspection feature.

## Implementation notes

- Keep validation strict and explicit
- `--pane-id` should use Zellij's existing pane-id parsing conventions
- `--tab-id` should use Zellij's existing tab-id handling and must resolve to an existing tab or fail normally
- No silent fallback, no guessing, no hidden compatibility layer
- Prefer the smallest internal additions needed to bridge CLI parsing to existing screen instructions

## Testing and docs

Each behavior patch should carry its own verification:

- CLI parsing / help coverage
- action-to-screen routing tests
- screen-level tests proving the intended break / move instruction is emitted with the expected focus behavior
- user-facing CLI docs updated in the same patch that introduces the command

## Planned patch split

1. `0001-zellij-expose-break-pane-cli.patch`
2. `0002-zellij-add-move-pane-to-tab-cli.patch`

## Out of scope follow-up

Once the Zellij patch set exists, `yeetnyoink` can switch from plugin pipes to the new CLI actions and existing discovery commands. That downstream change is not part of this patch-authoring task.
