#!/bin/bash
# WSL NixOS installer - build and output the WSL installer tarball
# Usage: sh <(curl -sL https://smallstepman.github.io/wsl.sh)

set -e

NIX_CONFIG_DIR="$HOME/.config/nix"

if [ ! -d "$NIX_CONFIG_DIR" ]; then
    echo "==> Cloning config repo..."
    mkdir -p "$HOME/.config"
    git clone https://github.com/smallstepman/smallstepman.github.io "$NIX_CONFIG_DIR"
fi

cd "$NIX_CONFIG_DIR"
echo "==> Building WSL installer..."
nix build ".#nixosConfigurations.wsl.config.system.build.installer"
echo "==> Done. Installer at: $NIX_CONFIG_DIR/result"
