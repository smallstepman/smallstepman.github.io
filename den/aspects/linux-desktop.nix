{ den, lib, inputs, ... }: {

  den.aspects.linux-desktop = {
    nixos = { config, pkgs, lib, ... }: {
      imports = [
        inputs.niri.nixosModules.niri
        inputs.noctalia.nixosModules.default
      ];

      hardware.bluetooth.enable = true;
      services.power-profiles-daemon.enable = true;
      services.upower.enable = true;

      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.addons = with pkgs; [
          qt6Packages.fcitx5-chinese-addons
          fcitx5-gtk
          fcitx5-hangul
          fcitx5-mozc
        ];
        fcitx5.waylandFrontend = true;
      };

      environment.systemPackages = with pkgs; [
        wl-clipboard
        wezterm
      ];

      programs.niri.enable = true;
      programs.niri.package = pkgs.niri-unstable;

      services.noctalia-shell.enable = true;

      services.xserver.windowManager.i3.enable = true;

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --xsessions ${config.services.displayManager.sessionData.desktops}/share/xsessions";
            user = "greeter";
          };
        };
      };

      services.xserver.enable = true;
      services.xserver.xkb.layout = "us";

      services.keyd = {
        enable = true;
        keyboards.default = {
          ids = [ "*" ];
          settings.main = {
            leftmeta    = "leftcontrol";
            leftcontrol = "leftalt";
            leftalt     = "leftmeta";
            rightalt    = "rightmeta";
            rightcontrol = "rightalt";
            rightmeta   = "rightcontrol";
          };
        };
      };
    };

    homeManager = { pkgs, lib, config, ... }:
      let
        librewolfProfile = "default-release";
        yny      = "/Users/m/Projects/yeetnyoink/target/release/yny";
        ynyFlags = [ "--log-file=/tmp/yeetnyoink/debug.log" "--profile" "--log-append" "--config=/home/m/.config/yeetnyoink/config-dev.toml" ];
        ynyArgv  = args: [ yny ] ++ ynyFlags ++ args;                  # for niri (argv list)
        ynyDbg   = lib.concatStringsSep " " ([ yny ] ++ ynyFlags);    # for mango/hyprland (shell string)
      in
      {
      imports = [
        inputs.noctalia.homeModules.default
        inputs.yeetnyoink.homeManagerModules.default
      ];

      programs.yeet-and-yoink.enable = true;

      programs.niri.settings = {
        hotkey-overlay = {
          skip-at-startup = true;
        };
        prefer-no-csd = true;
        input = {
          mod-key = "Alt";
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
          {
            matches = [
              { app-id = "^librewolf$"; }
            ];
            draw-border-with-background = false;
            opacity = 0.85;
          }
          {
            matches = [
              { app-id = "^(brave|brave-browser|com\\.brave\\.Browser)$"; }
            ];
            draw-border-with-background = false;
            opacity = 0.85;
          }
          {
            matches = [
              { app-id = "^(code|Code|code-url-handler)$"; }
            ];
            draw-border-with-background = false;
            opacity = 0.85;
          }
          {
            matches = [
              { app-id = "^(emacs|Emacs|emacsclient|org\\.gnu\\.Emacs)$"; }
            ];
            draw-border-with-background = false;
            opacity = 0.85;
          }
        ];

        outputs."Virtual-1".scale = 2.0;

        layout = {
          always-center-single-column = true;
          gaps = 8;
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

        workspaces = { };

        environment = {
          NIXOS_OZONE_WL = "1";
        };

        binds =
          {
            "Mod+T".action.spawn = ynyArgv [ "focus-or-cycle" "--app-id" "org.wezfurlong.wezterm" "--spawn" "wezterm" ];
            "Mod+Shift+T".action.spawn = "wezterm";

            "Mod+S".action.spawn = ynyArgv [ "focus-or-cycle" "--app-id" "librewolf" "--spawn" "librewolf" ];
            "Mod+Shift+S".action.spawn = "librewolf";

            "Mod+P".action.spawn = ynyArgv [ "focus-or-cycle" "--app-id" "spotify" "--spawn" "spotify" "--summon" ];

            "Mod+Space".action.spawn = "wlr-which-key";
            "Mod+Q".action.close-window = {};

            "Mod+R".action.switch-preset-column-width = {};
            "Mod+Shift+F".action.maximize-column = {};
            "Mod+F".action.fullscreen-window = {};
            "Mod+Minus".action.set-column-width = "-10%";
            "Mod+Equal".action.set-column-width = "+10%";
            "Mod+W".action.toggle-column-tabbed-display = {};
            "Mod+Slash".action.toggle-overview = {};

            "Mod+H".action.focus-column-left-or-last = {};
            "Mod+N".action.spawn = ynyArgv [ "focus" "west" ];
            "Mod+E".action.spawn = ynyArgv [ "focus" "south" ];
            "Mod+I".action.spawn = ynyArgv [ "focus" "north" ];
            "Mod+O".action.spawn = ynyArgv [ "focus" "east" ];
            "Mod+Return".action.focus-column-right-or-first = {};

            "Mod+J".action.consume-or-expel-window-left = {};
            "Mod+L".action.spawn = ynyArgv [ "move" "west" ];
            "Mod+U".action.spawn = ynyArgv [ "move" "south" ];
            "Mod+Y".action.spawn = ynyArgv [ "move" "north" ];
            "Mod+Semicolon".action.spawn = ynyArgv [ "move" "east" ];
            "Mod+Backslash".action.consume-or-expel-window-right = {};

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

      home.packages = [
        (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
          ${pkgs.emacs-pgtk}/bin/emacsclient -e \
            '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
            2>/dev/null || true
        '')

        pkgs.brave
        pkgs.chromium
        pkgs.clang
        (pkgs.librewolf.override {
          extraPolicies = config.programs.librewolf.policies;
        })
        pkgs.pywalfox-native
        pkgs.activitywatch
        pkgs.valgrind
        pkgs.foot
        pkgs.grim
        pkgs.slurp

        pkgs.wlr-which-key
        pkgs.git-repo-manager

        (pkgs.writeShellScriptBin "setup-my-tools" ''
          set -e

          echo "==> Syncing git repositories..."
          ${pkgs.git-repo-manager}/bin/grm repos sync config --config ~/.config/grm/repos.yaml

          echo "==> Regenerating Noctalia color templates..."
          noctalia-shell ipc call colorscheme regenerate || true

          echo "==> Bootstrap complete!"
        '')
      ];

      xdg.configFile = {
        "wezterm/wezterm.lua".text = builtins.readFile ../../../dotfiles/by-host/vm/wezterm.lua;

        "rbw/config.json".enable = lib.mkForce false;

        "wlr-which-key/config.yaml".text = builtins.readFile ../../../dotfiles/by-host/vm/wlr-which-key-config.yaml;

        "noctalia/user-templates.toml".source = ../../../dotfiles/by-host/vm/noctalia-user-templates.toml;
        "noctalia/emacs-template.el".source = ../editors/emacs/doom/themes/noctalia-template.el;
        "noctalia/wezterm-colors-template.lua".source = ../../../dotfiles/by-host/vm/wezterm-colors-template.lua;
        "nvim/lua/matugen-template.lua".source = ../editors/neovim/lazyvim/lua/matugen-template.lua;
      };

      programs.wayprompt = {
        enable = true;
        package = pkgs.wayprompt;
      };

      programs.noctalia-shell = {
        enable = true;
        settings = ../../../dotfiles/by-host/vm/noctalia.json;
      };

      programs.librewolf = {
        enable = true;
        # Keep the actual browser package in home.packages; HM is only used
        # for profile generation because the wrapped package path is broken here.
        package = null;
        profiles.${librewolfProfile} = {
          id = 0;
          isDefault = true;
          settings = {
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "sidebar.verticalTabs" = false;
            "sidebar.revamp" = false;
          };
          userChrome = builtins.readFile ../../../dotfiles/by-host/vm/librewolf/userChrome.css;
        };
        policies = {
          AppAutoUpdate                 = false;
          BackgroundAppUpdate           = false;
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
          BlockAboutConfig              = false;
          BlockAboutProfiles            = true;
          BlockAboutSupport             = true;
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
            "pywalfox@frewacom.org" = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi";
              installation_mode = "force_installed";
            };
            "{3c078156-979c-498b-8990-85f7987dd929}" = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/sidebery/latest.xpi";
              installation_mode = "force_installed";
            };
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
            "browser-bridge@yeetnyoink" = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/yeetnyoink-browser-bridge/latest.xpi";
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

      home.file.".librewolf/${librewolfProfile}/chrome/autohide.css".source =
        ../../../dotfiles/by-host/vm/librewolf/autohide.css;

      mozilla.librewolfNativeMessagingHosts = [ pkgs.pywalfox-native ];

      home.pointerCursor = {
        name = "Vanilla-DMZ";
        package = pkgs.vanilla-dmz;
        size = 128;
      };

      home.activation.createNoctaliaThemeDirs =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p "$HOME/.local/share/noctalia/emacs-themes"
        '';

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

      systemd.user.services.pywalfox-boot = {
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
    };
  };

}
