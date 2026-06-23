{ config, pkgs, ... }: {
  # ── Host declarations ─────────────────────────────────────────────────
  den.hosts.aarch64-linux.vm-aarch64.hostName = "vm-macbook";
  den.hosts.aarch64-linux.vm-aarch64.users.m = { };

  den.hosts.aarch64-darwin.macbook-pro-m1.users.m = { };

  den.hosts.x86_64-linux.jimi.users.s = {
    isNormalUser = true;
    hashedPassword = "$6$fhySpewi.hTKt.1D$nfheFtKH358q9dKSgrHGsgfzIsot4MgHQiT/A4YMB3hLe00CxTiiGr94qJZGsmFMOIbVMxqGq5emtrWJFWEwD1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
    ];
  };

  # ── MacBook Pro M1 ────────────────────────────────────────────────────
  den.aspects.macbook-pro-m1 = {
    includes = [
      config.den.aspects.activitywatch
      config.den.aspects.authorization
      config.den.aspects.containers
      config.den.aspects.desktop-apps
      config.den.aspects.devtools
      config.den.aspects.editors.emacs
      config.den.aspects.editors.neovim
      config.den.aspects.editors.vscode
      config.den.aspects.git
      config.den.aspects.keyboard.kanata
      config.den.aspects.keyboard.skhd
      config.den.aspects.network
      config.den.aspects.nix-daemon
      config.den.aspects.shell
      config.den.aspects.ssh-pam
      config.den.aspects.storage
      config.den.aspects.system-defaults
      config.den.aspects.touchid
      config.den.aspects.uniclip
      config.den.aspects.window-manager
    ];
  };

  # ── VM (aarch64) ──────────────────────────────────────────────────────
  den.aspects.vm-aarch64 = {
    includes = [
      config.den.aspects.activitywatch
      config.den.aspects.authorization.sudo
      config.den.aspects.authorization.touchid.vm
      config.den.aspects.authorization.wayprompt
      config.den.aspects.desktop-apps
      config.den.aspects.desktop.browsers
      config.den.aspects.desktop.cursor
      config.den.aspects.desktop.greetd
      config.den.aspects.desktop.input
      config.den.aspects.desktop.niri
      config.den.aspects.desktop.noctalia
      config.den.aspects.desktop.power
      config.den.aspects.desktop.wlr-which-key
      config.den.aspects.devtools
      config.den.aspects.editors.emacs
      config.den.aspects.editors.neovim
      config.den.aspects.editors.vscode
      config.den.aspects.git
      config.den.aspects.git.vm-signing
      config.den.aspects.hardware.bluetooth
      config.den.aspects.hardware.boot
      config.den.aspects.hardware.disk.vm-default
      config.den.aspects.hardware.fonts
      config.den.aspects.network.base
      config.den.aspects.network.kube-tunnel
      config.den.aspects.nix.settings
      config.den.aspects.secrets
      config.den.aspects.shell
      config.den.aspects.shell.wezterm-vm
      config.den.aspects.ssh-pam
      config.den.aspects.virtualization.core
      config.den.aspects.virtualization.flatpak
      config.den.aspects.vmware
    ];
  };

  # ── Jimi (x86_64) ─────────────────────────────────────────────────────
  den.aspects.jimi = {
    includes = [
      config.den.aspects.devtools
      config.den.aspects.hardware.boot.jimi
      config.den.aspects.hardware.cooling
      config.den.aspects.hardware.disk.jimi
      config.den.aspects.hardware.nvidia
      config.den.aspects.hardware.nvidia.gpu-monitoring
      config.den.aspects.monitoring
      config.den.aspects.network.tailscale
      config.den.aspects.nix.settings.jimi
      config.den.aspects.services.vllm
      config.den.aspects.shell
      config.den.aspects.ssh-pam.jimi

      ({ host, ... }: {
        nixos = { config, pkgs, lib, ... }: {
          networking.hostName = "jimi";
          networking.networkmanager.enable = true;
          networking.networkmanager.ensureProfiles.profiles."Preconfigured-WiFi" = {
            connection = { id = "Siema"; type = "wifi"; autoconnect = true; };
            wifi = { ssid = "Siema"; mode = "infrastructure"; };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "p79sqKgG2DyRlh";
            };
          };

          users.users.root = {
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
            ];
            hashedPassword = "$6$fhySpewi.hTKt.1D$nfheFtKH358q9dKSgrHGsgfzIsot4MgHQiT/A4YMB3hLe00CxTiiGr94qJZGsmFMOIbVMxqGq5emtrWJFWEwD1";
          };

          security.sudo.wheelNeedsPassword = false;

          system.stateVersion = "26.05";
        };
      })
    ];
  };
}
