{ den, pkgs, ... }: {
  # ── Host declarations ─────────────────────────────────────────────────
  den.hosts.aarch64-linux.vm-aarch64 = {
    hostName = "vm-macbook";
    users.m = { };
  };

  den.hosts.aarch64-darwin.macbook-pro-m1.users.m = { };

  den.hosts.x86_64-linux.jimi.users.s.classes = [ "user" "homeManager" ];

  # ── User m (cross-platform) ───────────────────────────────────────────
  den.aspects.m = {
    includes = [
      den.batteries.primary-user
      (den.batteries.user-shell "zsh")

      # Cross-platform user features
      den.aspects.shell
      den.aspects.editors.emacs
      den.aspects.editors.neovim
      den.aspects.git
      den.aspects.devtools
    ];
  };

  # ── User s (Jimi) ────────────────────────────────────────────────────
  den.aspects.s = {
    includes = [
      den.batteries.primary-user
      (den.batteries.user-shell "zsh")
    ];

    user = {
      hashedPassword = "!";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
      ];
    };
  };

  # ── MacBook Pro ────────────────────────────────────────────────────
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
      den.aspects.network.base
      den.aspects.network.kube-tunnel
      den.aspects.nix.settings
      den.aspects.secrets
      den.aspects.shell
      den.aspects.shell.wezterm-vm
      den.aspects.ssh-pam
      den.aspects.uniclip
      den.aspects.virtualization.core
      den.aspects.virtualization.flatpak
      den.aspects.vmware
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

      ({ host, ... }: {
        nixos = { config, pkgs, lib, ... }: {
          networking.hostName = "jimi";
          networking.networkmanager.enable = true;

          users.users.root = {
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
            ];
            hashedPassword = "!";
          };

          security.sudo.wheelNeedsPassword = false;

          system.stateVersion = "26.05";
        };
      })
    ];
  };

}
