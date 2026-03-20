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

              repair_repo() {
                local root="$1"

                case "$root" in
                  /nixos-config|/Users/m/Projects|/Users/m/Projects/*) ;;
                  *) return 0 ;;
                esac

                "$git_bin" -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
                "$git_bin" -C "$root" config core.fileMode false
                "$git_bin" -C "$root" submodule foreach --quiet 'git config core.fileMode false' 2>/dev/null || true
              }

              if [ "$#" -eq 0 ]; then
                repair_repo /nixos-config
                exit 0
              fi

              for repo in "$@"; do
                repair_repo "$repo"
              done
            '';

            repairingGit = pkgs.writeShellScriptBin "git" ''
              set -euo pipefail

              git_bin=${pkgs.git}/bin/git
              realpath_bin=${pkgs.coreutils}/bin/realpath
              repair_bin=${repairSharedGitFileMode}/bin/repair-shared-git-filemode

              resolve_workdir() {
                local dir="$PWD"
                local work_tree=""
                local git_dir_only=0

                while [ "$#" -gt 0 ]; do
                  case "$1" in
                    -C)
                      [ "$#" -ge 2 ] || break
                      case "$2" in
                        /*) dir=$("$realpath_bin" -m "$2") ;;
                        *) dir=$("$realpath_bin" -m "$dir/$2") ;;
                      esac
                      shift 2
                      ;;
                    --work-tree)
                      [ "$#" -ge 2 ] || break
                      case "$2" in
                        /*) work_tree=$("$realpath_bin" -m "$2") ;;
                        *) work_tree=$("$realpath_bin" -m "$dir/$2") ;;
                      esac
                      shift 2
                      ;;
                    --work-tree=*)
                      case "''${1#*=}" in
                        /*) work_tree=$("$realpath_bin" -m "''${1#*=}") ;;
                        *) work_tree=$("$realpath_bin" -m "$dir/''${1#*=}") ;;
                      esac
                      shift
                      ;;
                    --git-dir)
                      [ "$#" -ge 2 ] || break
                      git_dir_only=1
                      shift 2
                      ;;
                    --git-dir=*)
                      git_dir_only=1
                      shift
                      ;;
                    --)
                      break
                      ;;
                    -c|--exec-path|--namespace|--super-prefix|--config-env)
                      [ "$#" -ge 2 ] || break
                      shift 2
                      ;;
                    --exec-path=*|--namespace=*|--super-prefix=*|--config-env=*)
                      shift
                      ;;
                    -*)
                      shift
                      ;;
                    *)
                      break
                      ;;
                  esac
                done

                if [ -n "$work_tree" ]; then
                  dir="$work_tree"
                elif [ "$git_dir_only" -eq 1 ]; then
                  return 1
                fi

                printf '%s\n' "$dir"
              }

              if workdir=$(resolve_workdir "$@"); then
                if root=$("$git_bin" -C "$workdir" rev-parse --show-toplevel 2>/dev/null); then
                  "$repair_bin" "$root"
                fi
              fi

              exec "$git_bin" "$@"
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
            programs.git.package = repairingGit;

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
                run ${repairSharedGitFileMode}/bin/repair-shared-git-filemode /nixos-config
              '';

            home.activation.ensureKubeconfig =
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                if [ -f /nixos-generated/kubeconfig ]; then
                  mkdir -p "$HOME/.kube"
                  cp /nixos-generated/kubeconfig "$HOME/.kube/config"
                  chmod 600 "$HOME/.kube/config"
                  if ${pkgs.kubectl}/bin/kubectl config get-contexts orbstack >/dev/null 2>&1; then
                    ${pkgs.kubectl}/bin/kubectl config use-context orbstack
                  fi
                fi
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

            systemd.user.services.kubectl-orbstack-tunnel = {
              Unit = {
                Description = "SSH tunnel to macOS for OrbStack K8s API (port 26443)";
                After = [ "network.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${pkgs.writeShellScript "kubectl-tunnel" ''
                  set -euo pipefail
                  KUBECTL_TUNNEL_SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ControlMaster=auto -o ControlPath=$HOME/.ssh/control-k8s-%h-%p-%r -o ControlPersist=10m"
                  while true; do
                    /run/current-system/sw/bin/ssh -N -T $KUBECTL_TUNNEL_SSH_OPTS -L 26443:localhost:26443 m@192.168.130.1
                    sleep 5
                  done
                ''}";
                Restart = "always";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };
          };
      })
    ];
  };
}
