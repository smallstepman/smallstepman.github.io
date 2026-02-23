{ inputs, pkgs, ... }:

let
  awImportScreentimeSrc = pkgs.applyPatches {
    name = "aw-import-screentime-src";
    src = inputs.aw-import-screentime-src;
    patches = [ ../../patches/aw-import-screentime.patch ];
  };
  awAutomationScriptsRoot = "/Users/USER/.config/activitywatch/scripts";
in
{
  homebrew = {
    enable = true;
    casks  = [
      "activitywatch"
      "karabiner-elements"
      "claude"
      "discord"
      "gimp"
      "google-chrome"
      "leader-key"
      "lm-studio"
      "loop"
      "launchcontrol"
      "mullvad-vpn"
      "spotify"
    ];

    brews = [
      "gnupg"
      "kanata"
      "kanata-tray"
    ];

    masApps = {
      "Calflow"    = 6474122188;
      "Journal It"  = 6745241760;
      "Noir"        = 1592917505;
      "Perplexity"  = 6714467650;
      "Tailscale"   = 1475387142;
      "Telegram"    = 747648890;
      "Vimlike"     = 1584519802;
      "Wblock"      = 6746388723;
    };
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.m = {
    home = "/Users/m";
    shell = pkgs.zsh;
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "m";

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

  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };


  # Uniclip: encrypted clipboard sharing between macOS and NixOS VM.
  # Server listens on localhost only; an SSH reverse tunnel carries traffic to the VM.
  launchd.user.agents.uniclip = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          /bin/wait4path /nix/store
          export UNICLIP_PASSWORD=$(${pkgs.rbw}/bin/rbw get uniclip-password)
          exec ${pkgs.uniclip}/bin/uniclip --secure --bind 127.0.0.1 -p 53701
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/uniclip-server.log";
      StandardErrorPath = "/tmp/uniclip-server.log";
    };
  };

  # SSH reverse tunnel: forwards the uniclip port into the VM so the VM client
  # can reach the macOS server at 127.0.0.1:53701 on either end.
  launchd.user.agents.uniclip-tunnel = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
          VMX="/Users/m/Virtual Machines.localized/NixOS 25.11 aarch64.vmwarevm/NixOS 25.11 aarch64.vmx"
          while true; do
            VM_IP=$("$VMRUN" -T fusion getGuestIPAddress "$VMX" 2>/dev/null)
            if [ -n "$VM_IP" ] && [ "$VM_IP" != "unknown" ]; then
              /usr/bin/ssh -N \
                -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                -R 53701:127.0.0.1:53701 m@"$VM_IP"
            fi
            sleep 5
          done
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/uniclip-tunnel.log";
      StandardErrorPath = "/tmp/uniclip-tunnel.log";
    };
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

  launchd.user.agents.activitywatch-sync-aw-to-calendar = {
    serviceConfig = {
      ProgramArguments = [
        "/usr/bin/osascript"
        "-l"
        "JavaScript"
        "${awAutomationScriptsRoot}/synchronize.js"
      ];
      RunAtLoad = true;
      StartInterval = 1800;
      WorkingDirectory = awAutomationScriptsRoot;
      StandardOutPath = "/tmp/aw-sync-aw-to-calendar.out.log";
      StandardErrorPath = "/tmp/aw-sync-aw-to-calendar.err.log";
    };
  };

  launchd.user.agents.activitywatch-sync-ios-screentime-to-aw = {
    serviceConfig = {
      ProgramArguments = [
        "/Applications/LaunchControl.app/Contents/MacOS/fdautil"
        "exec"
        "/bin/bash"
        "${awAutomationScriptsRoot}/run_sync.sh"
      ];
      EnvironmentVariables = {
        AW_IMPORT_SRC = "${awImportScreentimeSrc}";
      };
      RunAtLoad = true;
      StartInterval = 3600;
      WorkingDirectory = awAutomationScriptsRoot;
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
        "${awAutomationScriptsRoot}/bucketize.js"
      ];
      RunAtLoad = true;
      StartInterval = 900;
      WorkingDirectory = awAutomationScriptsRoot;
      StandardOutPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.out.log";
      StandardErrorPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.err.log";
    };
  };
}
