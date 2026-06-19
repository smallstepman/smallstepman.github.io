#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ]; then
  set -a; source .env; set +a
fi
: "${WIFI_SSID:?Set WIFI_SSID in .env}"
: "${WIFI_PSK:?Set WIFI_PSK in .env}"
TMPFILE=$(mktemp /tmp/iso-expr.XXXXXX.nix)
trap 'rm -f "$TMPFILE"' EXIT
cat > "$TMPFILE" <<'NIXEOF'
let
  f = builtins.getFlake "/home/m/smallstepman.github.io";
  g = builtins.getFlake "/tmp/nix-generated";
  lib = f.inputs.nixpkgs.lib;
  pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
  outputs = f.lib.mkOutputs { generated = g; };
  jimi = outputs.nixosConfigurations.jimi;
  installer = f.inputs.unattended-installer.lib.diskoInstallerWrapper jimi {
    flake = null;
    successAction = "reboot";
    showProgress = true;
    config = {
      # WiFi driver for TP-Link Archer T2U Plus (RTL8821AU)
      boot.kernelPackages = pkgs.linuxPackages_6_18;
      boot.initrd.kernelModules = [ "rtw88_core" "rtw88_usb" "rtw88_88xxa" "rtw88_8821a" "rtw88_8821au" ];

      # WiFi via NetworkManager with preconfigured profile
      networking.networkmanager = {
        enable = true;
        ensureProfiles.profiles = {
          "Preconfigured-WiFi" = {
            connection = {
              id = "SSID_PLACEHOLDER";
              type = "wifi";
              autoconnect = true;
            };
            wifi = {
              ssid = "SSID_PLACEHOLDER";
              mode = "infrastructure";
            };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "PSK_PLACEHOLDER";
            };
          };
        };
      };

      systemd.services."unattended-installer-progress" = {
        wantedBy = [ "multi-user.target" ];
        unitConfig.After = [ "getty.target" ];
        unitConfig.Conflicts = [ "getty@tty8.service" ];
        serviceConfig.Type = "simple";
        path = [ pkgs.tmux pkgs.coreutils pkgs.kbd pkgs.nix-output-monitor ];
        script = ''
          set -xeufo pipefail
          env -i ${pkgs.tmux}/bin/tmux start \; show -g
          ${pkgs.tmux}/bin/tmux new-session -d -s unattended-installer /bin/sh -lc "journalctl -fo cat -u unattended-installer.service 2>&1 | ${pkgs.nix-output-monitor}/bin/nom; /bin/sh"
          ${pkgs.kbd}/bin/openvt -v --wait --login --console=8 --force --switch -- env -i TERM=linux ${pkgs.tmux}/bin/tmux attach-session -t unattended-installer
        '';
      };
    };
  };
in
  installer.config.system.build.isoImage
NIXEOF
sed -i "s/SSID_PLACEHOLDER/${WIFI_SSID}/g" "$TMPFILE"
sed -i "s/PSK_PLACEHOLDER/${WIFI_PSK}/g" "$TMPFILE"
nix build --impure -f "$TMPFILE"
