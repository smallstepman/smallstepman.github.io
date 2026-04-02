# Zellij Plugin Removal Implementation Plan

> **For agentic workers:** this plan reflects the current three-command design. The earlier break-pane/move-pane-to-tab-only plan has been superseded.

**Goal:** produce four upstream-ready Zellij patch files in `/nixos-config/patches` that replace the custom `plugins/zellij-bridge` flow with public CLI actions.

**Target patch series:**

1. `zellij-0001-add-move-pane-to-tab-cli.patch`
2. `zellij-0002-add-session-transfer-groundwork.patch`
3. `zellij-0003-add-move-pane-to-session-cli.patch`
4. `zellij-0004-add-move-tab-to-session-cli.patch`

## Approach

Treat the repo as the artifact host and the upstream Zellij checkout as the implementation workspace. Keep patch 1 as the same-session move feature, split the cross-session transport into its own groundwork patch, then build the two public cross-session commands on top of that plumbing. Export each logical change as a plain unified diff patch, update the local Nix override to the final patch list, and verify the patches apply cleanly on a fresh checkout.

## File structure

- Reference spec: `docs/superpowers/spec/2026-03-21-zellij-plugin-removal-design.md`
- Create: `patches/zellij-0001-add-move-pane-to-tab-cli.patch`
- Create: `patches/zellij-0002-add-session-transfer-groundwork.patch`
- Create: `patches/zellij-0003-add-move-pane-to-session-cli.patch`
- Create: `patches/zellij-0004-add-move-tab-to-session-cli.patch`
- Temporary workspace: upstream Zellij checkout used for implementation and verification

## Task outline

- Implement and export `move-pane-to-tab`
- Export the shared session transfer groundwork
- Implement and export `move-pane-to-session` with live pane transfer
- Implement and export `move-tab-to-session` with live tab transfer
- Update `den/mk-config-outputs.nix` to reference the four final patch files
- Verify sequential patch application on a clean upstream checkout
- Re-run the relevant build/test checks that exercise the Zellij derivation and the new commands

## Notes

- Cross-session moves must preserve live state, not recreate panes or tabs from layout
- Keep the command surface script-friendly and use stable IDs where applicable
- Avoid adding unrelated Zellij features or a new plugin control path
