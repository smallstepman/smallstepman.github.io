{ ... }: {
  den.aspects.uniclip = {
    darwin = import ./_darwin.nix;

    provides.to-users.homeManager = { pkgs, lib, ... }:
      lib.mkIf pkgs.stdenv.isLinux {
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
  };
}
