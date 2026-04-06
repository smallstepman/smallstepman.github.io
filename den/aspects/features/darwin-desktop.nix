{ den, inputs, lib, ... }: {
  den.aspects.darwin-desktop = {
    includes = [
      ({ host, ... }:
        lib.optionalAttrs (host.class == "darwin") {
          darwin = { pkgs, ... }: {
            imports = [ inputs.mac-app-util.darwinModules.default ];

            homebrew.casks = [
              "karabiner-elements"
              "claude"
              "discord"
              "gimp"
              "google-chrome"
              "leader-key"
              "lm-studio"
              "loop"
              "spotify"
              "swiftbar"
              "wezterm@nightly"
            ];
            homebrew.brews = [
              "kanata"
              "kanata-tray"
            ];
            homebrew.masApps = {
              "Calflow" = 6474122188;
              "Journal It" = 6745241760;
              "Noir" = 1592917505;
              "Perplexity" = 6714467650;
              "Telegram" = 747648890;
              "Vimlike" = 1584519802;
              "Wblock" = 6746388723;
              # "radio-garden-live" = 1339670993; 
            };

            system.defaults.CustomUserPreferences = {
              "com.apple.finder" = {
                AppleShowAllFiles = true;
                ShowPathbar = true;
                ShowStatusBar = true;
                _FXShowPosixPathInTitle = true;
                FXPreferredViewStyle = "Nlsv";
                CreateDesktop = false;
              };

              "com.apple.dock" = {
                autohide = true;
                tilesize = 36;
                magnification = true;
                largesize = 64;
                "minimize-to-application" = true;
                "show-recents" = false;
                "mru-spaces" = false;
                "expose-animation-duration" = 0.1;
                "autohide-delay" = 0.0;
                "autohide-time-modifier" = 0;
              };

              NSGlobalDomain = {
                KeyRepeat = 1;
                InitialKeyRepeat = 8;
                ApplePressAndHoldEnabled = false;
                "com.apple.mouse.scaling" = 0.0;
                "com.apple.mouse.tapBehavior" = 1;
                "com.apple.trackpad.scaling" = 10.0;
                NSWindowShouldDragOnGesture = true;
                NSAutomaticWindowAnimationsEnabled = false;
                NSWindowResizeTime = 0.001;
                NSStatusItemSpacing = 2;
                NSStatusItemSelectionPadding = 2;
              };

              "com.apple.screencapture" = {
                location = "/Users/m/Pictures/Screenshots";
                type = "png";
              };

              "com.apple.menuextra.clock" = {
                DateFormat = "EEE MMM d  H:mm";
              };

              "com.apple.speech.recognition.AppleSpeechRecognition.prefs" = {
                DictationIMAllowAudioDucking = false;
              };

              "com.apple.SpeechRecognitionCore" = {
                AllowAudioDucking = false;
              };
            };

            launchd.user.agents.openwebui = {
              serviceConfig = {
                ProgramArguments = [
                  "/bin/bash" "-c"
                  ''
                    /bin/wait4path /nix/store
                    mkdir -p "/Users/m/.local/state/open-webui"/{static,data,hf_home,transformers_home}
                    export PATH=${pkgs.uv}/bin:$PATH
                    export STATIC_DIR="/Users/m/.local/state/open-webui/static"
                    export DATA_DIR="/Users/m/.local/state/open-webui/data"
                    export HF_HOME="/Users/m/.local/state/open-webui/hf_home"
                    export SENTENCE_TRANSFORMERS_HOME="/Users/m/.local/state/open-webui/transformers_home"
                    export WEBUI_URL="http://localhost:8080"
                    export SCARF_NO_ANALYTICS=True
                    export DO_NOT_TRACK=True
                    export ANONYMIZED_TELEMETRY=False
                    cd "/Users/m/.local/state/open-webui"
                    exec ${pkgs.uv}/bin/uvx --python 3.11 open-webui@latest serve --host 127.0.0.1 --port 8080
                  ''
                ];
                RunAtLoad = true;
                KeepAlive = true;
                StandardOutPath = "/tmp/openwebui.log";
                StandardErrorPath = "/tmp/openwebui.log";
              };
            };

            launchd.user.agents.yny-warm-helper = {
              serviceConfig = {
                ProgramArguments = [
                  "/Users/m/.cargo/target/release/yny"
                  "--config"
                  "/Users/m/yny.config.dev.toml"
                  "--profile"
                  "warm-helper"
                  "serve"
                  "--socket"
                  "/tmp/yny-warm.sock"
                ];
                RunAtLoad = true;
                KeepAlive = true;
                LimitLoadToSessionType = "Aqua";
                ProcessType = "Interactive";
                StandardOutPath = "/tmp/yny-warm-helper.log";
                StandardErrorPath = "/tmp/yny-warm-helper.log";
              };
            };

            services.yabai.enable = true;
            services.skhd = {
              enable = true;
              package = pkgs.skhd;
              skhdConfig = builtins.readFile ../../../dotfiles/by-host/darwin/skhdrc;
            };

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
          };

          homeManager = { pkgs, ... }: {
            imports = [ inputs.mac-app-util.homeManagerModules.default ];

            home.activation.emacs-trampolines = let
              emacs = "${pkgs.emacs-pgtk}/bin/emacs";
              emacsclient = "${pkgs.emacs-pgtk}/bin/emacsclient";
            in ''
              # Create Emacs.app and EmacsClient.app trampolines for Spotlight
              nix run github:hraban/mac-app-util -- mktrampoline "${emacs}" /Applications/Emacs.app
              nix run github:hraban/mac-app-util -- mktrampoline "${emacsclient}" /Applications/EmacsClient.app
            '';

            xdg.configFile = {
              "kanata-tray" = {
                source = ../../../dotfiles/by-host/darwin/kanata/tray;
                recursive = true;
              };
              "kanata" = {
                source = ../../../dotfiles/by-host/darwin/kanata/config-macbook-iso;
                recursive = true;
              };
            };
          };
        })
    ];
  };
}
