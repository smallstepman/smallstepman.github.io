#!/bin/bash
# rpi - NixOS Raspberry Pi 4 server setup
# Usage: rpi {bootstrap|switch|install|ssh}
# Standalone: sh <(curl -sL https://smallstepman.github.io/rpi.sh)

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
NIXADDR="${NIXADDR:-}"
NIXPORT="${NIXPORT:-22}"
NIXUSER="${NIXUSER:-m}"
NIXINSTALLUSER="${NIXINSTALLUSER:-root}"
NIXNAME="${NIXNAME:-rpi4-server}"
NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/.config/nix}"

SSH_OPTIONS="-o StrictHostKeyChecking=accept-new"
BOOTSTRAP_SSH_OPTIONS="-o PubkeyAuthentication=no -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
INSTALL_SSH_PASSWORD="${INSTALL_SSH_PASSWORD:-root}"

HOST_SSH_PUBKEY_FILE="${HOST_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
GENERATED_DIR="$NIX_CONFIG_DIR/machines/generated"

# ─── Helpers ────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

# Find RPI4 on network
rpi_detect_ip() {
    echo "Detecting Raspberry Pi on network..."
    local ip
    ip=$(nmap -sn 192.168.1.0/24 2>/dev/null | grep -i raspberry | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [ -z "$ip" ]; then
        read -rp "Could not auto-detect RPI4 IP. Enter manually: " ip
    fi
    echo "$ip"
}

# ─── Prepare Host Auth Keys ────────────────────────────────────────────────

rpi_prepare_host_authorized_keys() {
    [ -f "$HOST_SSH_PUBKEY_FILE" ] || die "SSH public key not found: $HOST_SSH_PUBKEY_FILE"
    mkdir -p "$GENERATED_DIR"
    cp "$HOST_SSH_PUBKEY_FILE" "$GENERATED_DIR/rpi-host-authorized-keys"
}

# ─── Prepare SOPS Age Key ──────────────────────────────────────────────────

rpi_prepare_sops_age_key() {
    echo "Preparing SOPS age key on RPI4..."
    mkdir -p "$GENERATED_DIR"
    
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        sudo mkdir -p /var/lib/sops-nix
        sudo chmod 700 /var/lib/sops-nix
        if [ ! -f /var/lib/sops-nix/key.txt ]; then
            sudo nix-shell -p age --run "age-keygen -o /var/lib/sops-nix/key.txt"
            sudo chmod 600 /var/lib/sops-nix/key.txt
        fi
        sudo nix-shell -p age --run "age-keygen -y /var/lib/sops-nix/key.txt"
    ' | tr -d '\r' > "$GENERATED_DIR/rpi-age-pubkey"

    if ! grep -q '^age1' "$GENERATED_DIR/rpi-age-pubkey"; then
        die "Failed to fetch RPI4 sops age public key"
    fi
    
    echo "Age key collected successfully"
}

# ─── Collect Secrets ────────────────────────────────────────────────────────

rpi_collect_secrets() {
    touch "$NIX_CONFIG_DIR/machines/secrets.yaml"
    git -C "$NIX_CONFIG_DIR" add -f machines/secrets.yaml
    (cd "$NIX_CONFIG_DIR" && nix --extra-experimental-features 'nix-command flakes' run "$NIX_CONFIG_DIR#collect-secrets")
    git -C "$NIX_CONFIG_DIR" reset -q -- machines/secrets.yaml
}

# ─── Detect Drives ──────────────────────────────────────────────────────────

rpi_detect_drives() {
    echo "Detecting USB drives on RPI4..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        echo "=== Block devices ==="
        lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN
        echo ""
        echo "=== USB devices ==="
        lsusb
        echo ""
        echo "=== Disk IDs ==="
        ls -la /dev/disk/by-id/ 2>/dev/null || echo "No disk IDs available"
    '
    
    echo ""
    echo "Please update machines/rpi4.nix with correct device paths"
    echo "Use /dev/disk/by-id/ for stable device naming"
}

# ─── Bootstrap ───────────────────────────────────────────────────────────────

cmd_bootstrap() {
    echo "=== RPI4 NixOS Bootstrap ==="
    echo ""
    
    if [ -z "$NIXADDR" ]; then
        NIXADDR=$(rpi_detect_ip)
    fi
    
    echo "Target: ${NIXADDR}"
    echo ""
    
    echo "==> Preparing host authorized keys..."
    rpi_prepare_host_authorized_keys
    
    echo "==> Generating SOPS age key..."
    rpi_prepare_sops_age_key
    
    echo "==> Detecting drives..."
    rpi_detect_drives
    
    echo "==> Collecting secrets..."
    git -C "$NIX_CONFIG_DIR" add machines/generated/rpi-age-pubkey machines/generated/rpi-host-authorized-keys
    rpi_collect_secrets
    
    echo ""
    echo "=== Bootstrap preparation complete ==="
    echo ""
    echo "Next steps:"
    echo "1. Update machines/rpi4.nix with your drive IDs"
    echo "2. Run: rpi install"
    echo ""
}

# ─── Install NixOS ──────────────────────────────────────────────────────────

cmd_install() {
    if [ -z "$NIXADDR" ]; then
        die "NIXADDR not set. Run 'rpi bootstrap' first or set NIXADDR manually"
    fi
    
    echo "=== Installing NixOS on RPI4 ==="
    echo "Target: ${NIXADDR}"
    echo ""
    
    echo "Enter LUKS encryption password (will be required on every boot):"
    read -rs LUKS_PASSWORD
    echo ""
    
    echo "$LUKS_PASSWORD" | sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        cat > /tmp/luks-password'
    
    echo "==> Installing NixOS..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" "
        sudo nixos-install \\
            --flake '/etc/nixos#${NIXNAME}' \\
            --no-root-passwd
        echo 'Installation complete!'
    "
    
    echo ""
    echo "=== Installation complete ==="
    echo ""
    echo "Reboot the RPI4:"
    echo "  ssh root@${NIXADDR} 'reboot'"
    echo ""
    echo "After reboot, SSH as user 'm':"
    echo "  ssh m@${NIXADDR}"
}

# ─── Switch Configuration ───────────────────────────────────────────────────

cmd_switch() {
    if [ -z "$NIXADDR" ]; then
        NIXADDR=$(rpi_detect_ip)
    fi
    
    echo "Switching NixOS config on RPI4 at ${NIXADDR}..."
    
    rsync -avz -e "ssh $SSH_OPTIONS -p $NIXPORT" \
        --exclude='.git' --exclude='result' \
        "$NIX_CONFIG_DIR/" "${NIXUSER}@${NIXADDR}:/etc/nixos/"
    
    ssh $SSH_OPTIONS -p "$NIXPORT" "${NIXUSER}@${NIXADDR}" \
        "sudo nixos-rebuild switch --flake '/etc/nixos#${NIXNAME}'"
}

# ─── SSH ─────────────────────────────────────────────────────────────────────

cmd_ssh() {
    if [ -z "$NIXADDR" ]; then
        NIXADDR=$(rpi_detect_ip)
    fi
    
    if [ $# -gt 0 ]; then
        ssh $SSH_OPTIONS -p "$NIXPORT" "${NIXUSER}@${NIXADDR}" "$@"
    else
        ssh $SSH_OPTIONS -p "$NIXPORT" "${NIXUSER}@${NIXADDR}"
    fi
}

# ─── Help ────────────────────────────────────────────────────────────────────

cmd_help() {
    cat <<'EOF'
rpi - NixOS Raspberry Pi 4 server management

Usage: rpi <command>

Commands:
  help              Show this help
  bootstrap         Prepare RPI4 for installation (SSH, keys, secrets)
  install           Install NixOS to RPI4 drives
  switch            Apply configuration changes to running RPI4
  ssh [cmd]         SSH into RPI4, or run a command
  drives            Detect and display connected drives

Environment:
  NIXADDR           IP address of RPI4 (auto-detected if not set)
  NIXPORT           SSH port (default: 22)
  NIXUSER           Username (default: m)
  NIXNAME           Configuration name (default: rpi4-server)
  NIX_CONFIG_DIR    Path to nix config (default: ~/.config/nix)

Setup Workflow:
  1. Flash NixOS SD card image to SD
  2. Boot RPI4 with SD card
  3. Set root password: passwd
  4. Run: NIXADDR=<ip> rpi bootstrap
  5. Update machines/rpi4.nix with your drive IDs
  6. Run: NIXADDR=<ip> rpi install
  7. Reboot and remove SD card
  8. SSH into new NixOS installation

Post-Install:
  - Unlock LUKS drives at boot (password required)
  - Set up Tailscale: sudo tailscale up
  - Configure Jellyfin libraries
  - Add devices to Syncthing

EOF
}

# ─── Main ────────────────────────────────────────────────────────────────────

if [ $# -eq 0 ]; then
    cmd_help
    exit 0
fi

cmd="$1"
shift

case "$cmd" in
    help)       cmd_help ;;
    bootstrap)  cmd_bootstrap "$@" ;;
    install)    cmd_install "$@" ;;
    switch)     cmd_switch "$@" ;;
    ssh)        cmd_ssh "$@" ;;
    drives)     NIXADDR="${NIXADDR:-$(rpi_detect_ip)}"; rpi_detect_drives ;;
    *)          echo "Unknown command: $cmd"; cmd_help; exit 1 ;;
esac
