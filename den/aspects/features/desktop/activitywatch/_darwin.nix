{ inputs, ... }: { pkgs, ... }: {
  homebrew.casks = ["activitywatch"];
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
        patches = [ ../../../../../patches/aw-import-screentime.patch ];
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
}
