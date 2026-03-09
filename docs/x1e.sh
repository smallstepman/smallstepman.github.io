#!/bin/bash
# x1e.sh - NixOS installation for ThinkPad X1 Extreme Gen1 k3s homelab
# Usage: x1e {help|prepare|install|switch|setup-k3s}
# Standalone: sh <(curl -sL https://smallstepman.github.io/x1e.sh)

set -euo pipefail

# Configuration
NIXADDR="${NIXADDR:-}"
NIXPORT="${NIXPORT:-22}"
NIXUSER="${NIXUSER:-m}"
NIXINSTALLUSER="${NIXINSTALLUSER:-root}"
NIXNAME="thinkpad-x1-extreme-gen1"
NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/.config/nix}"
GENERATED_DIR="$NIX_CONFIG_DIR/machines/generated"

SSH_OPTIONS="-o StrictHostKeyChecking=accept-new"
BOOTSTRAP_SSH_OPTIONS="-o PubkeyAuthentication=no -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
INSTALL_SSH_PASSWORD="${INSTALL_SSH_PASSWORD:-root}"

# Helpers
die() { echo "error: $*" >&2; exit 1; }

cmd_help() {
    cat <<'EOF'
x1e - NixOS installation for ThinkPad X1 Extreme Gen1 k3s homelab

Usage: x1e <command>

Commands:
  help              Show this help
  prepare           Generate SSH keys and prepare secrets
  install <ip>      Install NixOS on the ThinkPad (run from another machine)
  switch            Apply configuration changes to installed system
  setup-k3s         Post-install k3s setup (NVIDIA runtime, etc.)
  ssh [cmd]         SSH into the machine, or run a command

Installation Steps:
  1. Create NixOS installer USB and boot the ThinkPad
  2. On ThinkPad: set root password with 'passwd'
  3. From another machine: x1e prepare
  4. From another machine: x1e install <thinkpad-ip>

Post-Install:
  5. Verify k3s: kubectl get nodes
  6. Verify GPU: nvidia-smi
  7. Verify Tailscale: tailscale status

Environment Variables:
  NIXADDR          Target IP/hostname (for switch, setup-k3s, ssh)
  NIXPORT          SSH port (default: 22)
  NIXUSER          Username (default: m)
  NIX_CONFIG_DIR   Path to nix config (default: ~/.config/nix)
EOF
}

cmd_prepare() {
    echo "Preparing secrets and SSH keys..."
    
    mkdir -p "$GENERATED_DIR"
    
    # Copy host SSH pubkey
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        cp "$HOME/.ssh/id_ed25519.pub" "$GENERATED_DIR/host-authorized-keys"
        echo "Host SSH key copied to $GENERATED_DIR/host-authorized-keys"
    else
        die "No SSH public key found at ~/.ssh/id_ed25519.pub"
    fi
    
    # Stage generated files
    git -C "$NIX_CONFIG_DIR" add -f "$GENERATED_DIR/host-authorized-keys" 2>/dev/null || true
    
    echo ""
    echo "Preparation complete. Next steps:"
    echo "  1. Boot ThinkPad from NixOS USB"
    echo "  2. Set root password on ThinkPad: passwd"
    echo "  3. Run: x1e install <thinkpad-ip>"
}

wait_for_ssh() {
    local addr="$1"
    local user="${2:-root}"
    echo "Waiting for SSH on ${user}@${addr}..."
    while true; do
        if sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${user}@${addr}" "echo ok" >/dev/null 2>&1; then
            echo "SSH connected!"
            return 0
        fi
        sleep 2
    done
}

cmd_install() {
    local addr="${1:-}"
    [ -z "$addr" ] && die "Usage: x1e install <target-ip>"
    
    [ -d "$NIX_CONFIG_DIR" ] || die "Nix config not found: $NIX_CONFIG_DIR"
    [ -f "$GENERATED_DIR/host-authorized-keys" ] || die "Run 'x1e prepare' first"
    
    echo "Installing NixOS on ThinkPad X1 Extreme at $addr..."
    echo ""
    
    wait_for_ssh "$addr" "root"
    
    # Create temporary disko config on target
    echo "Creating disko configuration..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "root@$addr" "cat > /tmp/disko.nix" << 'DISKOEOF'
{ disko.devices = {
  disk = {
    main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            name = "boot";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          nixos = {
            name = "nixos";
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}; }
DISKOEOF

    # Run disko to partition and format
    echo "Partitioning and formatting disk..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "root@$addr" '
        nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/disko.nix
    '
    
    # Mount the target
    echo "Mounting target filesystem..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "root@$addr" '
        mkdir -p /mnt/boot
        mount /dev/disk/by-label/nixos /mnt
        mount /dev/disk/by-label/boot /mnt/boot
    '
    
    # Copy NixOS configuration
    echo "Copying NixOS configuration..."
    scp $BOOTSTRAP_SSH_OPTIONS -r "$NIX_CONFIG_DIR"/* "root@$addr:/mnt/etc/nixos/"
    
    # Generate age key for sops
    echo "Generating age key for secrets..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "root@$addr" '
        mkdir -p /mnt/var/lib/sops-nix
        nix-shell -p age --run "age-keygen -o /mnt/var/lib/sops-nix/key.txt"
        chmod 700 /mnt/var/lib/sops-nix
        chmod 600 /mnt/var/lib/sops-nix/key.txt
        nix-shell -p age --run "age-keygen -y /mnt/var/lib/sops-nix/key.txt"
    ' | tr -d '\r' > "$GENERATED_DIR/x1e-age-pubkey"
    
    if ! grep -q '^age1' "$GENERATED_DIR/x1e-age-pubkey"; then
        die "Failed to generate age key"
    fi
    
    git -C "$NIX_CONFIG_DIR" add -f "$GENERATED_DIR/x1e-age-pubkey"
    
    # Install NixOS
    echo "Running nixos-install (this may take a while)..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "root@$addr" "
        nixos-install --flake '/mnt/etc/nixos#$NIXNAME' --no-root-passwd
    "
    
    echo ""
    echo "Installation complete! Rebooting..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "root@$addr" "reboot"
    
    echo ""
    echo "=============================================="
    echo "Installation complete!"
    echo "=============================================="
    echo ""
    echo "Next steps after reboot:"
    echo "  1. SSH into the machine: ssh m@$addr"
    echo "  2. Set environment: export NIXADDR=$addr"
    echo "  3. Run: x1e setup-k3s"
    echo ""
    echo "Verify GPU: ssh m@$addr nvidia-smi"
    echo "Verify k3s: ssh m@$addr kubectl get nodes"
}

cmd_switch() {
    local addr="${NIXADDR:-}"
    [ -z "$addr" ] && die "Set NIXADDR environment variable"
    
    echo "Applying configuration to $addr..."
    ssh $SSH_OPTIONS -p"$NIXPORT" "$NIXUSER@$addr" "
        sudo nixos-rebuild switch --flake '/etc/nixos#$NIXNAME'
    "
}

cmd_setup_k3s() {
    local addr="${NIXADDR:-}"
    [ -z "$addr" ] && die "Set NIXADDR environment variable"
    
    echo "Setting up k3s NVIDIA support on $addr..."
    
    ssh $SSH_OPTIONS -p"$NIXPORT" "$NIXUSER@$addr" '
        # Wait for k3s to be ready
        echo "Waiting for k3s..."
        while ! kubectl get nodes 2>/dev/null; do
            sleep 5
        done
        
        # Install NVIDIA device plugin
        echo "Installing NVIDIA device plugin..."
        kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
        
        echo ""
        echo "NVIDIA device plugin installed."
        echo "Verify with: kubectl get pods -n kube-system"
        echo ""
        echo "To test GPU workloads:"
        echo "  kubectl run gpu-test --rm -it --image nvidia/cuda:11.8.0-base-ubuntu22.04 -- nvidia-smi"
    '
}

cmd_ssh() {
    local addr="${NIXADDR:-}"
    [ -z "$addr" ] && die "Set NIXADDR environment variable"
    
    if [ $# -gt 0 ]; then
        ssh $SSH_OPTIONS -p"$NIXPORT" "${NIXUSER}@${addr}" "$@"
    else
        ssh $SSH_OPTIONS -p"$NIXPORT" "${NIXUSER}@${addr}"
    fi
}

# Main
case "${1:-help}" in
    help)        cmd_help ;;
    prepare)     cmd_prepare ;;
    install)     shift; cmd_install "$@" ;;
    switch)      cmd_switch ;;
    setup-k3s)   cmd_setup_k3s ;;
    ssh)         shift; cmd_ssh "$@" ;;
    *)           echo "Unknown command: $1"; cmd_help; exit 1 ;;
esac
