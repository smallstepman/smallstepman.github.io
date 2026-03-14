{ den, lib, inputs, ... }: {

  den.aspects.linux-desktop = {
    nixos = { config, pkgs, lib, ... }: {
      imports = [
        inputs.niri.nixosModules.niri
        inputs.mangowc.nixosModules.mango
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

      programs.mango.enable = true;

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
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

    homeManager = { pkgs, lib, config, ... }: {
      imports = [
        inputs.noctalia.homeModules.default
        inputs.mangowc.hmModules.mango
      ];

      home.packages = [
        (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
          ${pkgs.emacs-pgtk}/bin/emacsclient -e \
            '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
            2>/dev/null || true
        '')

        pkgs.brave
        pkgs.ghostty
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

        inputs.mangowc.packages.${pkgs.stdenv.hostPlatform.system}.default
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
        "noctalia/emacs-template.el".source = ../../../dotfiles/common/doom/themes/noctalia-template.el;
        "noctalia/wezterm-colors-template.lua".source = ../../../dotfiles/by-host/vm/wezterm-colors-template.lua;
        "nvim/lua/matugen-template.lua".source = ../../../dotfiles/common/lazyvim/lua/matugen-template.lua;
      };

      programs.kitty = {
        enable = true;
        settings = {
          confirm_os_window_close = 0;
          allow_remote_control = "socket-only";
          listen_on = "unix:@kitty-{kitty_pid}";
        };
        keybindings = {
          "ctrl+d" = "launch --location=hsplit --cwd=current";
          "ctrl+shift+d" = "launch --location=vsplit --cwd=current";
        };
      };

      wayland.windowManager.hyprland = {
        enable = true;
        settings = {
          monitor = ",preferred,auto,1";
        };
      };

      programs.wayprompt = {
        enable = true;
        package = pkgs.wayprompt;
      };

      wayland.windowManager.mango = {
        enable = true;
        settings = builtins.readFile ../../../dotfiles/by-host/vm/mangowc.cfg;
        autostart_sh = ''
          mako &
        '';
      };

      programs.noctalia-shell = {
        enable = true;
        settings = ../../../dotfiles/by-host/vm/noctalia.json;
      };

      programs.librewolf = {
        enable = false;
        package = pkgs.librewolf;
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
