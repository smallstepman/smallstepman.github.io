{ den, pkgs, ... }: {
  # Apply each host declaration's hostName to its operating system.
  den.schema.host.includes = [ den.batteries.hostname ];

  # ── Host declarations ─────────────────────────────────────────────────
  den.hosts.aarch64-linux.vm-aarch64 = {
    hostName = "vm-macbook";
    users.m = { };
  };

  den.hosts.aarch64-linux.vm-aarch64-unattended-demo = {
    hostName = "vm-unattended-demo";
    # This image proves the installer path without pulling the normal user's
    # desktop Home Manager closure into the live ISO installation.
    users.m.classes = [ "user" ];
  };

  den.hosts.aarch64-darwin.macbook-pro-m1.users.m = { };

  den.hosts.x86_64-linux.jimi.users.s.classes = [ "user" "homeManager" ];

  den.hosts.x86_64-linux.work-vm = {
    hostName = "work-vm";
    users.work = { };
  };

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

  # ── User work (company VM) ─────────────────────────────────────────────
  den.aspects.work = {
    includes = [
      den.batteries.primary-user
      (den.batteries.user-shell "zsh")

      den.aspects.devtools
      den.aspects.editors.emacs
      den.aspects.editors.neovim
      den.aspects.editors.vscode
      den.aspects.shell
    ];

    # The account starts locked. The installer flow sets its local password
    # interactively, so no password material enters the repository.
    user = {
      hashedPassword = "!";
      extraGroups = [ "docker" ];
    };

    # Keep Git available without inheriting the personal Git identity,
    # signing key, credential helper, or Bitwarden integration.
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.git ];
    };
  };

  # ── MacBook Pro ────────────────────────────────────────────────────────
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
  den.aspects.vm-aarch64-base = {
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
      den.aspects.shell
      den.aspects.shell.wezterm-vm
      den.aspects.ssh-pam
      den.aspects.uniclip
      den.aspects.virtualization.core
      den.aspects.virtualization.flatpak
      den.aspects.vmware
    ];

    # Host includes configure the NixOS side of these aspects. Their Home
    # Manager side must be projected into the VM's declared users explicitly.
    provides.to-users.includes = [
      den.aspects.activitywatch
      den.aspects.authorization.touchid.vm
      den.aspects.authorization.wayprompt
      den.aspects.desktop.browsers
      den.aspects.desktop.cursor
      den.aspects.desktop.niri
      den.aspects.desktop.noctalia
      den.aspects.desktop.wlr-which-key
      den.aspects.editors.vscode
      den.aspects.git.vm-signing
      den.aspects.network.kube-tunnel
      den.aspects.shell.wezterm-vm
    ];
  };

  den.aspects.vm-aarch64 = {
    includes = [
      den.aspects.vm-aarch64-base
      den.aspects.secrets
    ];
  };

  # ── Work VM (x86_64, virt-manager) ─────────────────────────────────
  den.aspects.work-vm = {
    includes = [
      den.aspects.desktop.greetd
      den.aspects.desktop.niri
      den.aspects.desktop.noctalia
      den.aspects.desktop.wlr-which-key
      den.aspects.hardware.boot
      den.aspects.hardware.disk.work-vm
      den.aspects.hardware.fonts
      den.aspects.keyboard.kanata
      den.aspects.network.work-vm
      den.aspects.nix.settings.work-vm
      den.aspects.shell.wezterm-vm
      den.aspects.virtualization.docker
      den.aspects.virtualization.qemu-guest
      ({ host, ... }: {
        nixos = { config, pkgs, lib, ... }: {
          boot.kernelModules = [ "9p" "9pnet_virtio" ];
          fileSystems."/home/work/Projects" = {
            device = "hostshare";
            fsType = "9p";
            options = [ "trans=virtio" "version=9p2000.L" "msize=104857600" "nofail" ];
          };
        };
      })
    ];

    provides.to-users.includes = [
      den.aspects.desktop.browsers.work-vm
      den.aspects.desktop.niri
      den.aspects.desktop.noctalia
      den.aspects.desktop.wlr-which-key
      den.aspects.shell.wezterm-vm
    ];

    # The VMware Fusion guest runs on a Retina display and uses 2x scaling.
    # virt-manager exposes the same Virtual-1 output on a normal-density
    # display, where that scale turns 1280x800 into a 640x400 logical desktop.
    provides.to-users.homeManager = { lib, ... }: {
      programs.niri.settings.outputs."Virtual-1" = {
        mode = {
          width = 1920;
          height = 1200;
        };
        scale = lib.mkForce 1.0;
      };
    };
  };

  # ── Unattended installer demonstration VM ───────────────────────────────
  den.aspects.vm-aarch64-unattended-demo = {
    includes = [
      den.aspects.authorization.sudo
      den.aspects.hardware.boot
      den.aspects.hardware.disk.vm-default
      den.aspects.network.base
      den.aspects.nix.settings
      den.aspects.ssh-pam
      den.aspects.vmware

      ({ ... }: {
        nixos = { lib, ... }: {
          # The demonstration remains SSH-key accessible without including the
          # production VM's secret consumers or age identity.
          networking.hostName = lib.mkForce "vm-unattended-demo";

          users.users.m = {
            hashedPasswordFile = lib.mkForce null;
            hashedPassword = lib.mkForce "!";
            openssh.authorizedKeys.keyFiles = [ ./aspects/network/ssh/m.pub ];
          };

          security.sudo.wheelNeedsPassword = lib.mkForce false;
        };
      })
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
