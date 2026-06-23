{ inputs, ... }: { pkgs, ... }: {
  imports = [ inputs.mac-app-util.darwinModules.default ];

  homebrew.casks = [
    "claude"
    "discord"
    "gimp"
    "google-chrome"
    "lm-studio"
    "loop"
    "spotify"
    "swiftbar"
    "wezterm@nightly"
  ];
  homebrew.masApps = {
    "Calflow" = 6474122188;
    "Journal It" = 6745241760;
    "Noir" = 1592917505;
    "Perplexity" = 6714467650;
    "Telegram" = 747648890;
    "Vimlike" = 1584519802;
    "Wblock" = 6746388723;
  };

  launchd.user.agents.yny-warm-helper = {
    serviceConfig = {
      ProgramArguments = [
        "/Users/m/.cargo/target/release/yny"
        "--config" "/Users/m/yny.config.dev.toml"
        "--profile" "warm-helper"
        "serve" "--socket" "/tmp/yny-warm.sock"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/yny-warm-helper.log";
      StandardErrorPath = "/tmp/yny-warm-helper.log";
    };
  };
}
