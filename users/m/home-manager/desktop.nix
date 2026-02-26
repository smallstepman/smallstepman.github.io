# Desktop/GUI configuration: Wayland compositors, browsers, screenshots, services.
# Only imported by machines with a graphical session (not rpi, vps, GPU servers).
{ isWSL, inputs, ... }:

{ config, lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
in {
  home.packages = lib.optionals (isLinux && !isWSL) [
    # Called by Noctalia hooks/user-templates on wallpaper/dark-mode changes
    (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
      # Reload Noctalia theme in running Emacs daemon
      ${pkgs.emacs-pgtk}/bin/emacsclient -e \
        '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
        2>/dev/null || true
    '')

    pkgs.chromium
    (pkgs.librewolf.override {
      extraPolicies = config.programs.librewolf.policies;
    })
    pkgs.pywalfox-native
    pkgs.activitywatch # automated time tracker (Linux only; Darwin via homebrew cask)
    pkgs.fuzzel       # app launcher for Wayland
    pkgs.foot         # lightweight Wayland terminal
    pkgs.grim         # screenshots
    pkgs.slurp        # region selection

    # Wayland utilities
    inputs.mangowc.packages.${pkgs.system}.default  # window control
    pkgs.wlr-which-key                              # which-key for wlroots

    # Wallpaper
    pkgs.git-repo-manager                           # declarative git repo sync

    # Bootstrap script - run once after fresh install
    (pkgs.writeShellScriptBin "setup-my-tools" ''
      set -e

      echo "==> Syncing git repositories..."
      ${pkgs.git-repo-manager}/bin/grm repos sync config --config ~/.config/grm/repos.yaml

      echo "==> Regenerating Noctalia color templates..."
      noctalia-shell ipc call colorscheme regenerate || true

      echo "==> Bootstrap complete!"
    '')
  ];

  xdg.configFile = {} // (if isDarwin then {
    "activitywatch/scripts" = {
      source = ../activitywatch;
      recursive = true;
    };
  } else {}) // (if isLinux then {
    # Noctalia user templates and theme template inputs
    "noctalia/user-templates.toml".source = ../noctalia-user-templates.toml;
    "noctalia/emacs-template.el".source = ../doom/themes/noctalia-template.el;

    # Neovim matugen template (input for Noctalia user template → nvim base16 theme)
    "nvim/lua/matugen-template.lua".source = ../lazyvim/lua/matugen-template.lua;
  } else {});

  # Niri Wayland compositor configuration (Linux only)
  programs.niri.settings = lib.mkIf (isLinux && !isWSL) {
    hotkey-overlay = {
      skip-at-startup = true;
    };
    prefer-no-csd = true; # Client Side Decorations (title bars etc)
    input = {
      
      mod-key = "Alt";  # Ctrl ; Alt; Super;
      keyboard.xkb.layout = "us";
      keyboard.repeat-delay = 150;
      keyboard.repeat-rate = 50;
      touchpad = {
        tap = true;
        natural-scroll = true;
      };
    };

    window-rules = [
      {
        geometry-corner-radius = {
          top-left = 12.0;
          top-right = 12.0;
          bottom-right = 12.0;
          bottom-left = 12.0;
        };
      }
      {
        clip-to-geometry = true;
      }
    ];

    outputs."Virtual-1".scale = 2.0;

    layout = {
      gaps = 16;
      center-focused-column = "never";
      preset-column-widths = [
        { proportion = 1.0 / 3.0; }
        { proportion = 1.0 / 2.0; }
        { proportion = 2.0 / 3.0; }
      ];
      default-column-width.proportion = 0.5;
      focus-ring = {
        width = 2;
        active.color = "#7fc8ff";
        inactive.color = "#505050";
      };
    };

    spawn-at-startup = [
      { command = [ "mako" ]; }
    ];

    environment = {
      NIXOS_OZONE_WL = "1";
    };

    binds = {
      # Launch
      "Mod+T" = {
        action.spawn = "ghostty";
        repeat = false;
      };
      "Mod+S" = {
        action.spawn = "librewolf";
        repeat = false;
      };
      "Mod+Space".action.spawn = "wlr-which-key";
      "Mod+Q".action.close-window = {};
      # Layout
      "Mod+R".action.switch-preset-column-width = {};
      "Mod+F".action.maximize-column = {};
      "Mod+Shift+F".action.fullscreen-window = {};
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";
      "Mod+W".action.toggle-column-tabbed-display = {};
      "Mod+Slash".action.toggle-overview = {};

      # # Screenshots
      # "Print".action.screenshot = {};
      # "Mod+Print".action.screenshot-window = {};

      # # Lock
      # "Mod+Escape".action.spawn = "swaylock";

      # Session
      # "Mod+Shift+E".action.quit = {};

      # Focus
      "Mod+N".action.focus-column-left = {};
      "Mod+E".action.focus-window-or-workspace-down = {};
      "Mod+I".action.focus-window-or-workspace-up = {};
      "Mod+O".action.focus-column-right = {};

      # Move
      "Mod+H".action.consume-or-expel-window-left = {};
      "Mod+L".action.move-column-left = {};
      "Mod+U".action.move-window-down-or-to-workspace-down = {};
      "Mod+Y".action.move-window-up-or-to-workspace-up = {};
      "Mod+Semicolon".action.move-column-right = {};
      "Mod+Return".action.consume-or-expel-window-right = {};

      # Workspaces
      "Mod+f1".action.focus-workspace = 1;
      "Mod+f2".action.focus-workspace = 2;
      "Mod+f3".action.focus-workspace = 3;
      "Mod+f4".action.focus-workspace = 4;
      "Mod+f5".action.focus-workspace = 5;
      "Mod+f6".action.focus-workspace = 6;
      "Mod+f7".action.focus-workspace = 7;
      "Mod+f8".action.focus-workspace = 8;
      "Mod+f9".action.focus-workspace = 9;

      "Shift+f1".action.move-column-to-workspace = 1;
      "Shift+f2".action.move-column-to-workspace = 2;
      "Shift+f3".action.move-column-to-workspace = 3;
      "Shift+f4".action.move-column-to-workspace = 4;
      "Shift+f5".action.move-column-to-workspace = 5;
      "Shift+f6".action.move-column-to-workspace = 6;
      "Shift+f7".action.move-column-to-workspace = 7;
      "Shift+f8".action.move-column-to-workspace = 8;
      "Shift+f9".action.move-column-to-workspace = 9;

    };
  };

  # Wayprompt password prompt for Wayland sessions (Linux only)
  programs.wayprompt = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    package = pkgs.wayprompt;
  };

  # Mango Wayland compositor configuration (Linux only)
  wayland.windowManager.mango = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    settings = builtins.readFile ../mangowc.cfg;
    autostart_sh = ''
      mako &
    '';
  };

  # Noctalia shell configuration (Linux VM only)
  programs.noctalia-shell = lib.mkIf (isLinux && !isWSL) {
    enable = true;
    settings = ../noctalia.json;
  };

  programs.librewolf = {
    enable = false;
    package = pkgs.librewolf;
    policies = {
      # Updates & Background Services
      AppAutoUpdate                 = false;
      BackgroundAppUpdate           = false;

      # Feature Disabling
      DisableBuiltinPDFViewer       = true;
      DisableFirefoxStudies         = true;
      DisableFirefoxAccounts        = true;
      DisableFirefoxScreenshots     = true;
      DisableForgetButton           = true;
      DisableMasterPasswordCreation = true;
      DisableProfileImport          = true;
      DisableProfileRefresh         = true;
      DisableSetDesktopBackground   = true;
      DisablePocket                 = true;
      DisableTelemetry              = true;
      DisableFormHistory            = true;
      DisablePasswordReveal         = true;

      # Access Restrictions
      BlockAboutConfig              = false;
      BlockAboutProfiles            = true;
      BlockAboutSupport             = true;

      # UI and Behavior
      DisplayMenuBar                = "never";
      DontCheckDefaultBrowser       = true;
      HardwareAcceleration          = false;
      OfferToSaveLogins             = false;
      DefaultDownloadDirectory      = "/home/m/Downloads";
      Cookies = {
        "Allow" = [
          "https://addy.io"
          "https://element.io"
          "https://discord.com"
          "https://github.com"
          "https://lemmy.cafe"
          "https://proton.me"
        ];
        "Locked" = true;
      };
      ExtensionSettings = {
        # Pywalfox (dynamic theming based on wallpaper colors)
        "pywalfox@frewacom.org" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi";
          installation_mode = "force_installed";
        };
        # uBlock Origin
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "addon@darkreader.org" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
          installation_mode = "force_installed";
        };
        "vimium-c@gdh1995.cn" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-c/latest.xpi";
          installation_mode = "force_installed";
        };
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          installation_mode = "force_installed";
        };
      };
      FirefoxHome = {
        "Search" = false;
      };
      Preferences = {
        "browser.preferences.defaultPerformanceSettings.enabled" = false;
        "browser.startup.homepage" = "about:home";
        "browser.toolbar.bookmarks.visibility" = "newtab";
        "browser.toolbars.bookmarks.visibility" = "newtab";
        "browser.urlbar.suggest.bookmark" = false;
        "browser.urlbar.suggest.engines" = false;
        "browser.urlbar.suggest.history" = false;
        "browser.urlbar.suggest.openpage" = false;
        "browser.urlbar.suggest.recentsearches" = false;
        "browser.urlbar.suggest.topsites" = false;
        "browser.warnOnQuit" = false;
        "browser.warnOnQuitShortcut" = false;
        "places.history.enabled" = "false";
        "privacy.resistFingerprinting" = true;
        "privacy.resistFingerprinting.autoDeclineNoUserInputCanvasPrompts" = true;
      };
    };
  };

  mozilla.librewolfNativeMessagingHosts = lib.mkIf (isLinux && !isWSL) [ pkgs.pywalfox-native ];

  # Ensure writable output directories for Noctalia user templates
  home.activation.createNoctaliaThemeDirs = lib.mkIf (isLinux && !isWSL) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "$HOME/.local/share/noctalia/emacs-themes"
  '');

  # Uniclip clipboard client: connects to macOS server via SSH reverse tunnel
  systemd.user.services.uniclip = lib.mkIf (isLinux && !isWSL) {
    Unit = {
      Description = "Uniclip clipboard client (connects to macOS server via SSH tunnel)";
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
        exec ${pkgs.uniclip}/bin/uniclip --secure 127.0.0.1:53701
      ''}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.pywalfox-boot = lib.mkIf (isLinux && !isWSL) {
    Unit = {
      Description = "Install and update Pywalfox for LibreWolf on boot";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "pywalfox-boot" ''
        set -euo pipefail
        ${pkgs.pywalfox-native}/bin/pywalfox install --browser librewolf
        ${pkgs.pywalfox-native}/bin/pywalfox update
      ''}";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
