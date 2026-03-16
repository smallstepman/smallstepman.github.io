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

            repairSharedGitFileMode = pkgs.writeShellScriptBin "repair-shared-git-filemode" ''
              set -euo pipefail

              git_bin=${pkgs.git}/bin/git
              dirname_bin=${pkgs.coreutils}/bin/dirname
              find_bin=${pkgs.findutils}/bin/find
              projects_root=/Users/m/Projects

              repair_repo() {
                local root="$1"

                case "$root" in
                  /nixos-config|/Users/m/Projects/*) ;;
                  *) return 0 ;;
                esac

                "$git_bin" -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
                "$git_bin" -C "$root" config core.fileMode false
                "$git_bin" -C "$root" submodule foreach --quiet 'git config core.fileMode false' 2>/dev/null || true
              }

              repair_default_roots() {
                local git_entry
                declare -A seen_roots=()

                seen_roots[/nixos-config]=1

                if [ -d "$projects_root" ]; then
                  while IFS= read -r git_entry; do
                    seen_roots[$("$dirname_bin" "$git_entry")]=1
                  done < <(
                    "$find_bin" "$projects_root" \
                      '(' -type d -name .git -print -prune ')' -o \
                      '(' -type f -name .git -print ')'
                  )
                fi

                for root in "''${!seen_roots[@]}"; do
                  repair_repo "$root"
                done
              }

              if [ "$#" -eq 0 ]; then
                repair_default_roots
                exit 0
              fi

              for repo in "$@"; do
                repair_repo "$repo"
              done
            '';

            opencode = import ../../../dotfiles/common/opencode/modules/common.nix;
          in {
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
            programs.git.settings.gpg.program = "${pkgs.gnupg}/bin/gpg";

            services.gpg-agent.pinentry.package = pkgs.pinentry-tty;
            services.gpg-agent.extraConfig = "allow-preset-passphrase";

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

            home.activation.ensureHostDockerContext =
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                if ! ${pkgs.docker-client}/bin/docker context inspect host-mac >/dev/null 2>&1; then
                  run ${pkgs.docker-client}/bin/docker context create host-mac \
                    --docker "host=ssh://m@mac-host-docker"
                fi
              '';

            home.activation.ensureSharedGitFileMode =
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                run ${repairSharedGitFileMode}/bin/repair-shared-git-filemode
              '';

            systemd.user.services."repair-shared-git-filemode" = {
              Unit = {
                Description = "Repair Git fileMode for HGFS-backed shared repos";
                After = [ "default.target" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${repairSharedGitFileMode}/bin/repair-shared-git-filemode";
              };
              Install.WantedBy = [ "default.target" ];
            };

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
                ExecStartPre = "${pkgs.opencode}/bin/opencode models --refresh";
                ExecStart = "${pkgs.opencode}/bin/opencode serve --mdns --mdns-domain ${opencode.stableMdnsDomain} --port ${toString opencode.stablePort}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.opencode-web = {
              Unit = {
                Description = "OpenCode web interface";
                After = [ "default.target" ];
              };
              Service = {
                Type = "simple";
                ExecStartPre = "${pkgs.opencode}/bin/opencode models --refresh";
                ExecStart = "${pkgs.opencode}/bin/opencode web --mdns --mdns-domain ${opencode.webMdnsDomain} --port ${toString opencode.webPort}";
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
