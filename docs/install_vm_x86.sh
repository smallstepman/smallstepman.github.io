#!/usr/bin/env bash

# Run from the official x86_64 NixOS installer.
# This destroys /dev/vda and installs the work-vm configuration from main.

set -euo pipefail

readonly disk=/dev/vda
readonly flake='github:smallstepman/smallstepman.github.io/main#work-vm'
readonly disko_rev=ff8702b4de27f72b4c78573dfb89ec74e36abdf1
readonly installer_swap=/mnt/.installer-swap

if (( EUID != 0 )); then
  echo "Run this script as root: sudo bash $0" >&2
  exit 1
fi

if [[ ! -b "$disk" ]]; then
  echo "Expected the VirtIO system disk at $disk." >&2
  echo "Configure the VM disk bus as VirtIO and try again." >&2
  lsblk >&2
  exit 1
fi

echo "The following disk will be erased:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "$disk"
read -r -p "Type WIPE to continue: " confirmation
[[ "$confirmation" == WIPE ]] || exit 1

export NIX_CONFIG=$'experimental-features = nix-command flakes\nmax-jobs = 4\ncores = 0'

nix run "github:nix-community/disko/${disko_rev}#disko" -- \
  --mode destroy,format,mount \
  --yes-wipe-all-disks \
  --flake "$flake"

# Give the installer's RAM-backed writable Nix store disk-backed overflow.
# The full desktop closure is much larger than the stock ISO store allowance.
fallocate -l 48G "$installer_swap"
chmod 0600 "$installer_swap"
mkswap "$installer_swap" >/dev/null
swapon "$installer_swap"

if [[ $(findmnt -n -o FSTYPE /nix/.rw-store 2>/dev/null || true) == tmpfs ]]; then
  mount -o remount,size=64G /nix/.rw-store
fi

cleanup_swap() {
  nix-store --gc >/dev/null 2>&1 || true
  if swapon --noheadings --show=NAME | grep -Fxq "$installer_swap"; then
    if swapoff "$installer_swap"; then
      rm -f "$installer_swap"
    fi
  else
    rm -f "$installer_swap"
  fi
}
trap cleanup_swap EXIT

nixos-install \
  --flake "$flake" \
  --no-root-passwd \
  --no-channel-copy

nixos-enter --root /mnt -c 'passwd work'

cleanup_swap
trap - EXIT

sync
echo
echo "Installation complete. Detach the ISO and run: reboot"
