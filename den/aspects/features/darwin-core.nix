{ den, generated, inputs, lib, ... }: {
  den.aspects.darwin-core = {
    includes = [
      ({ host, ... }:
        lib.optionalAttrs (host.class == "darwin") {
        darwin = { pkgs, ... }: {
          imports = [ ../../../dotfiles/common/opencode/modules/darwin.nix ];

          system.stateVersion = 5;

          # This makes it work with the Determinate Nix installer.
          ids.gids.nixbld = 30000;

          # We use the determinate-nix installer which manages Nix for us,
          # so we don't want nix-darwin to do it.
          nix.enable = false;
          nix.extraOptions = ''
            experimental-features = nix-command flakes
            keep-outputs = true
            keep-derivations = true
          '';

          # Enable the Linux builder so we can run Linux builds on our Mac.
          nix.linux-builder = {
            enable = false;
            ephemeral = true;
            maxJobs = 4;
            config = ({ pkgs, ... }: {
              virtualisation = {
                cores = 6;
                darwin-builder = {
                  diskSize = 100 * 1024; # 100GB
                  memorySize = 32 * 1024; # 32GB
                };
              };

              environment.systemPackages = [
                pkgs.htop
              ];
            });
          };

          nix.settings.trusted-users = [ "@admin" ];

          # Determinate's nix.conf may not include nix.custom.conf; manage both.
          environment.etc."nix/nix.conf".text = ''
            build-users-group = nixbld
            !include /etc/nix/nix.custom.conf
          '';

          environment.etc."nix/nix.custom.conf".text = ''
            experimental-features = nix-command flakes
          '';

          # Make ad-hoc nixpkgs usage honor unfree defaults.
          environment.etc."nixpkgs/config.nix".text = ''
            { allowUnfree = true; }
          '';

          programs.zsh.enable = true;
          programs.zsh.shellInit = ''
            # Nix
            if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
              . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
            fi
            # End Nix
          '';

          programs.fish.enable = true;
          programs.fish.shellInit = ''
            # Nix
            if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
              source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
            end
            # End Nix
          '';

          environment.shells = with pkgs; [ bashInteractive zsh fish ];
          environment.systemPackages = with pkgs; [
            cachix
          ];

          # The user already exists via den identity, but nix-darwin still needs
          # these Darwin-specific fields to know the home directory and host SSH
          # trust configuration for host/guest integration.
            users.users.m = {
              home = "/Users/m";
              openssh.authorizedKeys.keyFiles = [
                (generated.requireFile "mac-host-authorized-keys")
              ];
            };

          services.openssh.enable = true;
          services.openssh.extraConfig = ''
            # Only listen on the VMware host/guest interface so sshd is not reachable
            # from other network interfaces (Wi-Fi, Ethernet, etc.).
            ListenAddress 192.168.130.1
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitRootLogin no
            X11Forwarding no
            AllowUsers m
          '';

          security.pam.services.sudo_local = {
            touchIdAuth = true;
            watchIdAuth = true;
            reattach = true;
          };

          homebrew.enable = true;
          homebrew.taps = [
            "lujstn/tap"
          ];
          homebrew.casks = [
            "activitywatch"
            "launchcontrol"
            # Nix-provided s3fs on Darwin links against the macFUSE runtime.
            "macfuse"
            "mullvad-vpn"
            "orbstack"
          ];
          homebrew.brews = [
            "gnupg"
            "pinentry-touchid"
          ];
          homebrew.masApps = {
            "Tailscale" = 1475387142;
          };

          launchd.user.agents.uniclip = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  set -euo pipefail
                  /bin/wait4path /nix/store
                  export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
                  UNICLIP_PASSWORD="$(${pkgs.rbw}/bin/rbw get uniclip-password)"
                  if [ -z "$UNICLIP_PASSWORD" ]; then
                    echo "uniclip: empty password from rbw" >&2
                    exit 1
                  fi
                  export UNICLIP_PASSWORD
                  exec ${pkgs.uniclip}/bin/uniclip --secure --bind 192.168.130.1 -p 53701
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/uniclip-server.log";
              StandardErrorPath = "/tmp/uniclip-server.log";
            };
          };

          launchd.user.agents.openwebui-tunnel = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  while true; do
                    /usr/bin/ssh-keygen -R "192.168.130.3" >/dev/null 2>&1 || true
                    /usr/bin/ssh -N \
                      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                      -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                      -R 18080:127.0.0.1:8080 m@192.168.130.3
                    sleep 5
                  done
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/openwebui-tunnel.log";
              StandardErrorPath = "/tmp/openwebui-tunnel.log";
            };
          };

          launchd.user.agents.activitywatch-tunnel = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  while true; do
                    /usr/bin/ssh-keygen -R "192.168.130.3" >/dev/null 2>&1 || true
                    /usr/bin/ssh -N \
                      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                      -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                      -R 5600:127.0.0.1:5600 m@192.168.130.3
                    sleep 5
                  done
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/activitywatch-tunnel.log";
              StandardErrorPath = "/tmp/activitywatch-tunnel.log";
            };
          };

          launchd.user.agents.activitywatch-sync-aw-to-calendar = {
            serviceConfig = {
              ProgramArguments = [
                "/usr/bin/osascript"
                "-l"
                "JavaScript"
                "/Users/m/.config/activitywatch/scripts/synchronize.js"
              ];
              RunAtLoad = true;
              StartInterval = 1800;
              WorkingDirectory = "/Users/m/.config/activitywatch/scripts";
              StandardOutPath = "/tmp/aw-sync-aw-to-calendar.out.log";
              StandardErrorPath = "/tmp/aw-sync-aw-to-calendar.err.log";
            };
          };

          launchd.user.agents.activitywatch-sync-ios-screentime-to-aw =
            let
              awImportScreentimeSrc = pkgs.applyPatches {
                name = "aw-import-screentime-src";
                src = inputs.aw-import-screentime-src;
                patches = [ ../../../patches/aw-import-screentime.patch ];
              };
            in {
              serviceConfig = {
                ProgramArguments = [
                  "/Applications/LaunchControl.app/Contents/MacOS/fdautil"
                  "exec"
                  "/bin/bash"
                  "/Users/m/.config/activitywatch/scripts/run_sync.sh"
                ];
                EnvironmentVariables = {
                  AW_IMPORT_SRC = "${awImportScreentimeSrc}";
                  PATH = "/etc/profiles/per-user/m/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin";
                };
                RunAtLoad = true;
                StartInterval = 3600;
                WorkingDirectory = "/Users/m/.config/activitywatch/scripts";
                StandardOutPath = "/tmp/aw-sync-ios-screentime-to-aw.out.log";
                StandardErrorPath = "/tmp/aw-sync-ios-screentime-to-aw.err.log";
              };
            };

          launchd.user.agents.activitywatch-bucketize-aw-and-sync-to-calendar = {
            serviceConfig = {
              ProgramArguments = [
                "/usr/bin/osascript"
                "-l"
                "JavaScript"
                "/Users/m/.config/activitywatch/scripts/bucketize.js"
              ];
              RunAtLoad = true;
              StartInterval = 900;
              WorkingDirectory = "/Users/m/.config/activitywatch/scripts";
              StandardOutPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.out.log";
              StandardErrorPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.err.log";
            };
          };
        };

        homeManager = { pkgs, ... }: {
          home.packages = [
            pkgs.ghostty-bin
            pkgs.skhd
            pkgs.cachix
            pkgs.gettext
            pkgs.sentry-cli
            pkgs.rsync
            pkgs.sshpass
          ];

          xdg.configFile = {
            "wezterm/wezterm.lua".text = builtins.readFile ../../../dotfiles/by-host/darwin/wezterm.lua;
            "activitywatch/scripts" = {
              source = ../../../dotfiles/by-host/darwin/activitywatch;
              recursive = true;
            };
          };
        };
      })
    ];
  };
}
