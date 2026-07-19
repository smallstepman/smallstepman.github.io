let
  configDir = builtins.getEnv "NIX_CONFIG_DIR";
  wifiSsid =
    let value = builtins.getEnv "WIFI_SSID";
    in if value == "" then throw "WIFI_SSID is required" else value;
  wifiPsk =
    let value = builtins.getEnv "WIFI_PSK";
    in if value == "" then throw "WIFI_PSK is required" else value;

  f = builtins.getFlake configDir;
  pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
  jimi = f.nixosConfigurations.jimi;

  installer = f.inputs.unattended-installer.lib.diskoInstallerWrapper jimi {
    flake = null;
    successAction = "reboot";
    showProgress = true;
    postInstall = ''
      ${pkgs.coreutils}/bin/install -Dm600 \
        /run/NetworkManager/system-connections/Preconfigured-WiFi.nmconnection \
        /mnt/etc/NetworkManager/system-connections/Preconfigured-WiFi.nmconnection
    '';

    config = {
      # Wi-Fi driver for TP-Link Archer T2U Plus (RTL8821AU).
      boot.kernelPackages = pkgs.linuxPackages_6_18;
      boot.initrd.kernelModules = [
        "rtw88_core"
        "rtw88_usb"
        "rtw88_88xxa"
        "rtw88_8821a"
        "rtw88_8821au"
      ];

      # This profile exists only in the secret-bearing installer closure. After
      # installation its runtime keyfile is copied into the target's persistent
      # NetworkManager state by postInstall above.
      networking.networkmanager = {
        enable = true;
        ensureProfiles.profiles.Preconfigured-WiFi = {
          connection = {
            id = wifiSsid;
            type = "wifi";
            autoconnect = true;
          };
          wifi = {
            ssid = wifiSsid;
            mode = "infrastructure";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = wifiPsk;
          };
        };
      };

      systemd.services.unattended-installer = {
        requires = [ "NetworkManager-ensure-profiles.service" ];
        after = [ "NetworkManager-ensure-profiles.service" ];
      };

      systemd.services.unattended-installer-progress = {
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
