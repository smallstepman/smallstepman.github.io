{
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
      den.aspects.activitywatch
      den.aspects.authorization
      den.aspects.containers
      den.aspects.desktop-apps
      den.aspects.devtools
      den.aspects.editors.emacs
      den.aspects.editors.neovim
      den.aspects.editors.vscode
      den.aspects.git
      den.aspects.identity
      den.aspects.keyboard.kanata
      den.aspects.keyboard.skhd
      den.aspects.network
      den.aspects.nix-daemon
      den.aspects.shell
      den.aspects.ssh-pam
      den.aspects.storage
      den.aspects.system-defaults
      den.aspects.touchid
      den.aspects.uniclip
      den.aspects.window-manager
      den.provides.define-user
      den.provides.primary-user
      (den.provides.user-shell "zsh")
    ];
  };

  # ── VM (aarch64) ──────────────────────────────────────────────────────
  den.aspects.vm-aarch64 = {
    includes = [
      den.aspects.activitywatch
      den.aspects.authorization.sudo
      den.aspects.authorization.touchid.vm
      den.aspects.authorization.wayprompt
      den.aspects.desktop-apps
      den.aspects.desktop.browsers
      den.aspects.desktop.cursor
      den.aspects.desktop.greetd
      den.aspects.desktop.input
      den.aspects.desktop.niri
      den.aspects.desktop.noctalia
      den.aspects.desktop.power
      den.aspects.desktop.wlr-which-key
      den.aspects.devtools
      den.aspects.editors.emacs
      den.aspects.editors.neovim
      den.aspects.editors.vscode
      den.aspects.git
      den.aspects.git.vm-signing
      den.aspects.hardware.bluetooth
      den.aspects.hardware.boot
      den.aspects.hardware.disk.vm-default
      den.aspects.hardware.fonts
      den.aspects.identity
      den.aspects.network.base
      den.aspects.network.kube-tunnel
      den.aspects.nix.settings
      den.aspects.secrets
      den.aspects.shell
      den.aspects.shell.wezterm-vm
      den.aspects.ssh-pam
      den.aspects.virtualization.core
      den.aspects.virtualization.flatpak
      den.aspects.vmware
      den.provides.hostname
      den.provides.define-user
      den.provides.primary-user
      (den.provides.user-shell "zsh")
    ];
  };

  # ── Jimi (x86_64) ─────────────────────────────────────────────────────
  den.aspects.jimi = {
    includes = [
      den.aspects.devtools
      den.aspects.hardware.boot.jimi
      den.aspects.hardware.cooling
      den.aspects.hardware.disk.jimi
      den.aspects.hardware.nvidia
      den.aspects.hardware.nvidia.gpu-monitoring
      den.aspects.monitoring
      den.aspects.network.tailscale
      den.aspects.nix.settings.jimi
      den.aspects.services.vllm
      den.aspects.shell
      den.aspects.ssh-pam.jimi
      den.provides.hostname
      den.provides.define-user
      den.provides.primary-user
      (den.provides.user-shell "zsh")

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
