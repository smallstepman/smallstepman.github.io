# Clipboard Sharing (macOS ↔ NixOS VM)

Clipboard is shared between the macOS host and NixOS VM using a patched build
of [uniclip](https://github.com/quackduck/uniclip) over an SSH reverse tunnel.
VMware Fusion's built-in clipboard was abandoned — it uses a GTK3/X11 plugin
(`libdndcp.so`) that does not work under Wayland.

## Architecture

```
macOS (host)                              NixOS VM (guest)
┌──────────────────────┐                 ┌──────────────────────┐
│ uniclip server       │                 │ uniclip client       │
│ --secure             │                 │ --secure             │
│ --bind 127.0.0.1     │◄────────────────│ 127.0.0.1:53701      │
│ -p 53701             │                 │                      │
│ UNICLIP_PASSWORD=... │                 │ UNICLIP_PASSWORD=... │
│ (from rbw)           │                 │ (from rbw)           │
│                      │                 │                      │
│ SSH -R tunnel ───────────── SSH ──────►│ sshd                 │
│ 53701→127.0.0.1:53701│                 │ remote fwd :53701    │
└──────────────────────┘                 └──────────────────────┘
```

- macOS uniclip binds **only** to `127.0.0.1:53701` (never exposed on the network)
- macOS opens an SSH **reverse tunnel** to the VM: remote port 53701 → `127.0.0.1:53701` on macOS
- VM uniclip connects to `127.0.0.1:53701` which the tunnel carries back to macOS
- Both sides use `--secure` (AES-GCM encryption); shared password from `rbw get uniclip-password`

## Uniclip patch

Uniclip upstream (`patches/uniclip-bind-and-env-password.patch`) was patched to add:

- `--bind/-b` flag: server binds to `bindAddr:port` instead of always `0.0.0.0:port`
- `UNICLIP_PASSWORD` env var: read password from environment before falling back to
  interactive `terminal.ReadPassword` (which requires a TTY — incompatible with launchd/systemd)
- Max args bumped from 4 to 8 to accommodate the new flags

Built from source as a `buildGoModule` in `flake.nix` (same pattern as `difi` and
`agent-of-empires`): non-flake `uniclip-src` input + overlay entry.

## macOS side

Two launchd user agents managed by nix-darwin in `users/m/darwin.nix`:

**`org.nixos.uniclip`** — uniclip server:
- Waits for `/nix/store` to be available (`/bin/wait4path`)
- Fetches password via `rbw get uniclip-password`
- Starts `uniclip --secure --bind 127.0.0.1 -p 53701`
- `KeepAlive = true` (launchd restarts on exit)
- Logs to `/tmp/uniclip-server.log`

**`org.nixos.uniclip-tunnel`** — SSH reverse tunnel:
- Loop: get VM IP via `vmrun getGuestIPAddress`, open SSH reverse tunnel
- `ssh -N -R 53701:127.0.0.1:53701 m@<VM_IP>` with 30s keepalive
- If SSH dies (VM reboot, network change), loop retries after 5s
- `KeepAlive = true`
- Logs to `/tmp/uniclip-tunnel.log`

## VM side

A systemd user service in `users/m/home-manager.nix`:

**`uniclip.service`** — uniclip client:
- Starts after `graphical-session.target` (Wayland must be up)
- Fetches password via `rbw get uniclip-password`
- Sets `WAYLAND_DISPLAY=wayland-1` and `XDG_RUNTIME_DIR=/run/user/$(id -u)`
- Starts `uniclip --secure 127.0.0.1:53701`
- `Restart=on-failure`, `RestartSec=5`

## Password management

The shared encryption password is stored in Bitwarden and fetched via `rbw` on
both sides. One-time setup:

```bash
# On macOS (generates and saves to Bitwarden in one step):
rbw generate --no-symbols 32 uniclip-password

# On VM (after rbw is unlocked and synced):
rbw sync
systemctl --user restart uniclip
```

## Files

| File | Role |
|------|------|
| `patches/uniclip-bind-and-env-password.patch` | Go patch adding `--bind` and `UNICLIP_PASSWORD` |
| `flake.nix` | `uniclip-src` non-flake input + `uniclip` buildGoModule overlay |
| `users/m/darwin.nix` | launchd agents: `uniclip` (server) and `uniclip-tunnel` (SSH tunnel) |
| `users/m/home-manager.nix` | `pkgs.uniclip` package + `systemd.user.services.uniclip` (VM client) |

## Debugging

```bash
# macOS — check agents are running:
launchctl list | grep uniclip

# macOS — tail logs:
tail -f /tmp/uniclip-server.log /tmp/uniclip-tunnel.log

# VM — check service:
systemctl --user status uniclip

# VM — manual test paste:
WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000 wl-paste
```
