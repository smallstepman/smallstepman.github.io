{ pkgs, ... }: {
  homebrew.casks = [ "karabiner-elements" "leader-key" ];
  homebrew.brews = [ "kanata" "kanata-tray" ];

  launchd.user.agents.kanata-tray = {
    serviceConfig = {
      ProgramArguments = [ "sudo" "/opt/homebrew/bin/kanata-tray" ];
      EnvironmentVariables = {
        KANATA_TRAY_CONFIG_DIR = "/Users/m/.config/kanata-tray";
        KANATA_TRAY_LOG_DIR = "/tmp";
      };
      StandardOutPath = "/tmp/kanata-try.out.log";
      StandardErrorPath = "/tmp/kanata-tray.err.log";
      RunAtLoad = true;
      KeepAlive = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
      ThrottleInterval = 20;
    };
  };
}
