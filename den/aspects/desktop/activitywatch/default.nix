{ inputs, pkgs, ... }: {
  den.aspects.activitywatch = {
    darwin = import ./_darwin.nix { inherit inputs; };

    nixos = { pkgs, ... }: {
      systemd.user.services.activitywatch-watcher-afk = {
        Unit = {
          Description = "ActivityWatch AFK watcher (remote macOS server)";
          After = [ "graphical-session.target" "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.activitywatch}/bin/aw-watcher-afk --host 127.0.0.1 --port 5600";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      systemd.user.services.activitywatch-watcher-window = {
        Unit = {
          Description = "ActivityWatch window watcher (remote macOS server)";
          After = [ "graphical-session.target" "network-online.target" ];
          Wants = [ "network-online.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.activitywatch}/bin/aw-watcher-window --host 127.0.0.1 --port 5600";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };

    homeManager = { ... }: {
      xdg.configFile."activitywatch/scripts" = {
        source = ./scripts;
        recursive = true;
      };
    };
  };
}
