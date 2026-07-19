{ inputs, pkgs, ... }: {
  den.aspects.activitywatch = {
    darwin = import ./_darwin.nix { inherit inputs; };

    nixos = { pkgs, ... }: {
      systemd.user.services.activitywatch-watcher-afk = {
        description = "ActivityWatch AFK watcher (remote macOS server)";
        after = [ "graphical-session.target" "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.activitywatch}/bin/aw-watcher-afk --host 127.0.0.1 --port 5600";
          Restart = "always";
          RestartSec = 5;
        };
      };

      systemd.user.services.activitywatch-watcher-window = {
        description = "ActivityWatch window watcher (remote macOS server)";
        after = [ "graphical-session.target" "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.activitywatch}/bin/aw-watcher-window --host 127.0.0.1 --port 5600";
          Restart = "always";
          RestartSec = 5;
        };
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
