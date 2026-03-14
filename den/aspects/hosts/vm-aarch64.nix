{ den, generated, inputs, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      den.aspects.linux-core
      den.aspects.secrets
      den.aspects.linux-desktop
      den.aspects.vmware
      den.provides.hostname

      ({ host, ... }: {
        nixos = { config, pkgs, lib, ... }: {
          imports = [
            inputs.disko.nixosModules.disko
          ];

          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.allowUnsupportedSystem = true;

          boot.initrd.availableKernelModules = [ "uhci_hcd" "ahci" "xhci_pci" "nvme" "usbhid" "sr_mod" ];
          boot.initrd.kernelModules = [ ];
          boot.kernelModules = [ ];
          boot.extraModulePackages = [ ];
          swapDevices = [ ];

          disko.devices = {
            disk.main = {
              device = lib.mkDefault "/dev/nvme0n1";
              type = "disk";
              content = {
                type = "gpt";
                partitions = {
                  ESP = {
                    size = "500M";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                      mountOptions = [ "umask=0077" ];
                    };
                  };
                  root = {
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

          boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

          fileSystems."/nixos-config" = {
            fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
            device = ".host:/nixos-config";
            options = [
              "umask=22"
              "uid=1000"
              "gid=1000"
              "allow_other"
              "auto_unmount"
              "defaults"
            ];
          };

          fileSystems."/nixos-generated" = {
            fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
            device = ".host:/nixos-generated";
            options = [
              "umask=22"
              "uid=1000"
              "gid=1000"
              "allow_other"
              "auto_unmount"
              "defaults"
            ];
          };

          fileSystems."/Users/m/Projects" = {
            fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
            device = ".host:/Projects";
            options = [
              "umask=22"
              "uid=1000"
              "gid=1000"
              "allow_other"
              "auto_unmount"
              "defaults"
            ];
          };

          networking.interfaces.enp2s0.useDHCP = true;

          sops.hostPubKey = lib.removeSuffix "\n"
            (generated.readFile "vm-age-pubkey");

          networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];

          systemd.services.openwebui-local-proxy = {
            description = "Expose tunneled Open WebUI on localhost:80";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:18080";
              Restart = "always";
              RestartSec = 1;
            };
          };

          users.users.m = {
            extraGroups = [ "lxd" ];
            openssh.authorizedKeys.keyFiles = [
              (generated.requireFile "host-authorized-keys")
            ];
          };
        };

        homeManager = { pkgs, lib, ... }:
          let
            vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";

            gpgPresetPassphraseLogin = pkgs.writeShellScriptBin "gpg-preset-passphrase-login" ''
              set -euo pipefail

              if ! passphrase="$(${pkgs.rbw}/bin/rbw get gpg-password-nixos-macbook-vm)"; then
                echo "gpg-preset-passphrase-login: failed to read gpg-password-nixos-macbook-vm from rbw" >&2
                exit 1
              fi

              if [ -z "$passphrase" ]; then
                echo "gpg-preset-passphrase-login: empty passphrase from rbw" >&2
                exit 1
              fi

              mapfile -t keygrips < <(
                ${pkgs.gnupg}/bin/gpg --batch --with-colons --with-keygrip --list-secret-keys ${vmGitSigningKey} \
                  | ${pkgs.gawk}/bin/awk -F: '$1 == "grp" && $10 != "" { print $10 }'
              )
              if [ "''${#keygrips[@]}" -eq 0 ]; then
                echo "gpg-preset-passphrase-login: failed to resolve keygrip for ${vmGitSigningKey}" >&2
                exit 1
              fi

              ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null
              for keygrip in "''${keygrips[@]}"; do
                printf '%s' "$passphrase" | ${pkgs.gnupg}/bin/gpg-preset-passphrase --preset "$keygrip"
              done
            '';

            opencode = import ../../../dotfiles/common/opencode/modules/common.nix;
          in {
            imports = [
              inputs.yeet-and-yoink.homeManagerModules.default
            ];

            home.packages = [
              pkgs.docker-client
              gpgPresetPassphraseLogin
            ];

            home.sessionVariables = {
              GENERATED_INPUT_DIR = "/nixos-generated";
              DOCKER_CONTEXT = "host-mac";
            };

            programs.rbw.settings.pinentry = pkgs.wayprompt;

            programs.git.signing.key = vmGitSigningKey;

            services.gpg-agent.pinentry.package = pkgs.pinentry-tty;
            services.gpg-agent.extraConfig = "allow-preset-passphrase";

            programs.yeet-and-yoink.enable = true;

            programs.zsh.initContent = lib.mkAfter ''

              # Auto-fix fileMode for git repos on VMware shared folders
              # (macOS reports all files as 755; git sees mode changes vs index)
              typeset -gA _git_filemode_fixed
              _fix_git_filemode() {
                if [[ "$PWD" == /Users/m/Projects/* ]] && [[ -d .git ]]; then
                  local root=$(git rev-parse --show-toplevel 2>/dev/null)
                  [[ -z "$root" ]] && return
                  [[ -n "''${_git_filemode_fixed[$root]}" ]] && return
                  git config core.fileMode false 2>/dev/null
                  git submodule foreach --quiet 'git config core.fileMode false' 2>/dev/null
                  _git_filemode_fixed[$root]=1
                fi
              }
              add-zsh-hook chpwd _fix_git_filemode
              _fix_git_filemode
            '';

            programs.ssh = {
              enable = true;
              enableDefaultConfig = false;
              matchBlocks."mac-host-docker" = {
                hostname = "192.168.130.1";
                user = "m";
                identityFile = "~/.ssh/id_ed25519";
                controlMaster = "auto";
                controlPersist = "10m";
                controlPath = "~/.ssh/control-%h-%p-%r";
                serverAliveInterval = 30;
              };
            };

            programs.niri.settings = {
              hotkey-overlay = {
                skip-at-startup = true;
              };
              prefer-no-csd = true;
              input = {
                mod-key = "Alt";
                keyboard.xkb.layout = "us";
                keyboard.repeat-delay = 150;
                keyboard.repeat-rate = 50;
                touchpad = {
                  tap = true;
                  natural-scroll = true;
                };
              };

              window-rules = [
                {
                  geometry-corner-radius = {
                    top-left = 12.0;
                    top-right = 12.0;
                    bottom-right = 12.0;
                    bottom-left = 12.0;
                  };
                }
                {
                  clip-to-geometry = true;
                }
              ];

              outputs."Virtual-1".scale = 2.0;

              layout = {
                always-center-single-column = true;
                gaps = 16;
                center-focused-column = "never";
                preset-column-widths = [
                  { proportion = 1.0 / 3.0; }
                  { proportion = 1.0 / 2.0; }
                  { proportion = 2.0 / 3.0; }
                ];
                default-column-width.proportion = 0.5;
                focus-ring = {
                  width = 2;
                  active.color = "#7fc8ff";
                  inactive.color = "#505050";
                };
              };

              spawn-at-startup = [
                { command = [ "mako" ]; }
              ];

              workspaces = {
                "stash" = { };
              };

              environment = {
                NIXOS_OZONE_WL = "1";
              };

              binds =
                let
                  yny = "${pkgs.yeet-and-yoink}/bin/yeet-and-yoink";
                in {
                  "Mod+T".action.spawn = [
                    yny "focus-or-cycle"
                    "--app-id" "org.wezfurlong.wezterm"
                    "--spawn" "wezterm"
                  ];
                  "Mod+Shift+T".action.spawn = "wezterm";

                  "Mod+S".action.spawn = [
                    yny "focus-or-cycle"
                    "--app-id" "librewolf"
                    "--spawn" "librewolf"
                  ];
                  "Mod+Shift+S".action.spawn = "librewolf";

                  "Mod+P".action.spawn = [
                    yny "focus-or-cycle"
                    "--app-id" "spotify"
                    "--spawn" "spotify"
                    "--summon"
                  ];

                  "Mod+Space".action.spawn = "wlr-which-key";
                  "Mod+Q".action.close-window = {};

                  "Mod+R".action.switch-preset-column-width = {};
                  "Mod+F".action.maximize-column = {};
                  "Mod+Shift+F".action.fullscreen-window = {};
                  "Mod+Minus".action.set-column-width = "-10%";
                  "Mod+Equal".action.set-column-width = "+10%";
                  "Mod+W".action.toggle-column-tabbed-display = {};
                  "Mod+Slash".action.toggle-overview = {};

                  "Mod+N".action.spawn = [ yny "focus" "west" ];
                  "Mod+E".action.spawn = [ yny "focus" "south" ];
                  "Mod+I".action.spawn = [ yny "focus" "north" ];
                  "Mod+O".action.spawn = [ yny "focus" "east" ];

                  "Mod+H".action.consume-or-expel-window-left = {};
                  "Mod+L".action.spawn = [ yny "move" "west" ];
                  "Mod+U".action.spawn = [ yny "move" "south" ];
                  "Mod+Y".action.spawn = [ yny "move" "north" ];
                  "Mod+Semicolon".action.spawn = [ yny "move" "east" ];
                  "Mod+Return".action.consume-or-expel-window-right = {};

                  "Mod+f1".action.focus-workspace = 1;
                  "Mod+f2".action.focus-workspace = 2;
                  "Mod+f3".action.focus-workspace = 3;
                  "Mod+f4".action.focus-workspace = 4;
                  "Mod+f5".action.focus-workspace = 5;
                  "Mod+f6".action.focus-workspace = 6;
                  "Mod+f7".action.focus-workspace = 7;
                  "Mod+f8".action.focus-workspace = 8;
                  "Mod+f9".action.focus-workspace = 9;

                  "Shift+f1".action.move-column-to-workspace = 1;
                  "Shift+f2".action.move-column-to-workspace = 2;
                  "Shift+f3".action.move-column-to-workspace = 3;
                  "Shift+f4".action.move-column-to-workspace = 4;
                  "Shift+f5".action.move-column-to-workspace = 5;
                  "Shift+f6".action.move-column-to-workspace = 6;
                  "Shift+f7".action.move-column-to-workspace = 7;
                  "Shift+f8".action.move-column-to-workspace = 8;
                  "Shift+f9".action.move-column-to-workspace = 9;
                };
            };

            home.activation.ensureHostDockerContext =
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                if ! ${pkgs.docker-client}/bin/docker context inspect host-mac >/dev/null 2>&1; then
                  run ${pkgs.docker-client}/bin/docker context create host-mac \
                    --docker "host=ssh://m@mac-host-docker"
                fi
              '';

            systemd.user.services.gpg-preset-passphrase-login = {
              Unit = {
                Description = "Preset GPG signing passphrase on login";
                After = [ "default.target" "rbw-config.service" ];
                Wants = [ "rbw-config.service" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${gpgPresetPassphraseLogin}/bin/gpg-preset-passphrase-login";
                Restart = "on-failure";
                RestartSec = 30;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.opencode-serve = {
              Unit = {
                Description = "OpenCode stable server (serve mode)";
                After = [ "default.target" ];
              };
              Service = {
                Type = "simple";
                ExecStartPre = "${pkgs.llm-agents.opencode}/bin/opencode models --refresh";
                ExecStart = "${pkgs.llm-agents.opencode}/bin/opencode serve --mdns --mdns-domain ${opencode.stableMdnsDomain} --port ${toString opencode.stablePort}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.opencode-web = {
              Unit = {
                Description = "OpenCode web interface (patched dev)";
                After = [ "default.target" ];
              };
              Service = {
                Type = "simple";
                ExecStartPre = "${pkgs.opencode-dev}/bin/opencode models --refresh";
                ExecStart = "${pkgs.opencode-dev}/bin/opencode web --mdns --mdns-domain ${opencode.webMdnsDomain} --port ${toString opencode.webPort}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.uniclip = {
              Unit = {
                Description = "Uniclip clipboard client (direct connection to macOS server)";
                After = [ "graphical-session.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${pkgs.writeShellScript "uniclip-client" ''
                  set -euo pipefail
                  export XDG_RUNTIME_DIR=/run/user/$(id -u)
                  export PATH=${lib.makeBinPath [ pkgs.wl-clipboard ]}:$PATH
                  if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
                    export WAYLAND_DISPLAY=wayland-1
                  elif [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
                    export WAYLAND_DISPLAY=wayland-0
                  else
                    echo "uniclip: no wayland socket found in $XDG_RUNTIME_DIR" >&2
                    exit 1
                  fi
                  if [ ! -r /run/secrets/uniclip/password ]; then
                    echo "uniclip: /run/secrets/uniclip/password is missing" >&2
                    exit 1
                  fi
                  UNICLIP_PASSWORD="$(cat /run/secrets/uniclip/password)"
                  if [ -z "$UNICLIP_PASSWORD" ]; then
                    echo "uniclip: empty password from /run/secrets/uniclip/password" >&2
                    exit 1
                  fi
                  export UNICLIP_PASSWORD
                  exec ${pkgs.uniclip}/bin/uniclip --secure 192.168.130.1:53701
                ''}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };
          };
      })
    ];
  };
}
