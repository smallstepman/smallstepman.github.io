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

    homeManager = { pkgs, lib, config, ... }:
      let
        yny      = "/Projects/m/yeet-and-yoink/target/release/yny";
        ynyFlags = [ "--log-file=/tmp/yeet-and-yoink/debug.log" "--profile" "--log-append" ];
        ynyArgv  = args: [ yny ] ++ ynyFlags ++ args;                  # for niri (argv list)
        ynyDbg   = lib.concatStringsSep " " ([ yny ] ++ ynyFlags);    # for mango/hyprland (shell string)
      in
      {
      imports = [
        inputs.noctalia.homeModules.default
        inputs.mangowc.hmModules.mango
        inputs.yeet-and-yoink.homeManagerModules.default
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
        ];

        outputs."Virtual-1".scale = 2.0;

        layout = {
          always-center-single-column = true;
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

        workspaces = {
          "stash" = { };
        };

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
            "Mod+F".action.maximize-column = {};
            "Mod+Shift+F".action.fullscreen-window = {};
            "Mod+Minus".action.set-column-width = "-10%";
            "Mod+Equal".action.set-column-width = "+10%";
            "Mod+W".action.toggle-column-tabbed-display = {};
            "Mod+Slash".action.toggle-overview = {};

            "Mod+N".action.spawn = ynyArgv [ "focus" "west" ];
            "Mod+E".action.spawn = ynyArgv [ "focus" "south" ];
            "Mod+I".action.spawn = ynyArgv [ "focus" "north" ];
            "Mod+O".action.spawn = ynyArgv [ "focus" "east" ];

            "Mod+H".action.consume-or-expel-window-left = {};
            "Mod+L".action.spawn = ynyArgv [ "move" "west" ];
            "Mod+U".action.spawn = ynyArgv [ "move" "south" ];
            "Mod+Y".action.spawn = ynyArgv [ "move" "north" ];
            "Mod+Semicolon".action.spawn = ynyArgv [ "move" "east" ];
            "Mod+Return".action.consume-or-expel-window-right = {};

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
          monitor = ",preferred,auto,2";

          general = {
            gaps_in    = 8;
            gaps_out   = 16;
            border_size = 2;
            "col.active_border"   = "rgba(7fc8ffff)";
            "col.inactive_border" = "rgba(505050ff)";
            layout = "dwindle";
          };

          decoration = {
            rounding = 12;
            blur = {
              enabled = false;
            };
            shadow = {
              enabled = false;
            };
          };

          animations = {
            enabled = true;
            bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
            animation = [
              "windows,     1, 4, myBezier"
              "windowsOut,  1, 4, default, popin 80%"
              "border,      1, 8, default"
              "fade,        1, 6, default"
              "workspaces,  1, 4, default"
            ];
          };

          input = {
            kb_layout = "us";
            repeat_delay = 150;
            repeat_rate  = 50;
            touchpad = {
              natural_scroll   = true;
              tap-to-click     = true;
              drag_lock        = true;
            };
          };

          dwindle = {
            pseudotile        = true;
            preserve_split    = true;
            always_center_new = true;
          };

          misc = {
            force_default_wallpaper = 0;
            disable_hyprland_logo   = true;
          };

          "$mod" = "ALT";

          bind = [
            "$mod, T,           exec, ${ynyDbg} focus-or-cycle --app-id org.wezfurlong.wezterm --spawn wezterm"
            "$mod SHIFT, T,     exec, wezterm"
            "$mod, S,           exec, ${ynyDbg} focus-or-cycle --app-id librewolf --spawn librewolf"
            "$mod SHIFT, S,     exec, librewolf"
            "$mod, P,           exec, ${ynyDbg} focus-or-cycle --app-id spotify --spawn spotify --summon"
            "$mod, Space,       exec, wlr-which-key"
            "$mod, Q,           killactive"
            "$mod, F,           fullscreen, 1"

            "$mod, N, exec, ${ynyDbg} focus west"
            "$mod, E, exec, ${ynyDbg} focus south"
            "$mod, I, exec, ${ynyDbg} focus north"
            "$mod, O, exec, ${ynyDbg} focus east"

            "$mod SHIFT, N, exec, ${ynyDbg} move west"
            "$mod SHIFT, E, exec, ${ynyDbg} move south"
            "$mod SHIFT, I, exec, ${ynyDbg} move north"
            "$mod SHIFT, O, exec, ${ynyDbg} move east"

            "$mod, R, togglesplit"

            "$mod, F1, workspace, 1"
            "$mod, F2, workspace, 2"
            "$mod, F3, workspace, 3"
            "$mod, F4, workspace, 4"
            "$mod, F5, workspace, 5"
            "$mod, F6, workspace, 6"
            "$mod, F7, workspace, 7"
            "$mod, F8, workspace, 8"
            "$mod, F9, workspace, 9"

            "$mod SHIFT, F1, movetoworkspace, 1"
            "$mod SHIFT, F2, movetoworkspace, 2"
            "$mod SHIFT, F3, movetoworkspace, 3"
            "$mod SHIFT, F4, movetoworkspace, 4"
            "$mod SHIFT, F5, movetoworkspace, 5"
            "$mod SHIFT, F6, movetoworkspace, 6"
            "$mod SHIFT, F7, movetoworkspace, 7"
            "$mod SHIFT, F8, movetoworkspace, 8"
            "$mod SHIFT, F9, movetoworkspace, 9"
          ];

          bindm = [
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
          ];

          exec-once = [
            "mako"
          ];
        };
      };

      programs.wayprompt = {
        enable = true;
        package = pkgs.wayprompt;
      };

      wayland.windowManager.mango = {
        enable = true;
        autostart_sh = ''
          mako &
        '';
        settings = ''
          # Window appearance
          border_radius       = 12
          borderpx            = 2
          focuscolor          = 0x7fc8ffff
          bordercolor         = 0x505050ff
          rootcolor           = 0x1a1a2eff
          focused_opacity     = 1.0
          unfocused_opacity   = 0.95

          # Gaps
          gappih = 8
          gappiv = 8
          gappoh = 16
          gappov = 16

          # Animations
          animations                 = 1
          animation_type_open        = slide
          animation_type_close       = slide
          animation_fade_in          = 1
          animation_fade_out         = 1
          animation_duration_open    = 400
          animation_duration_close   = 400
          animation_duration_move    = 350
          animation_duration_tag     = 350
          animation_curve_open       = 0.46,1.0,0.29,1
          animation_curve_move       = 0.46,1.0,0.29,1
          animation_curve_close      = 0.08,0.92,0,1
          animation_curve_tag        = 0.46,1.0,0.29,1

          # Input
          xkb_rules_layout = us
          repeat_delay     = 150
          repeat_rate      = 50
          tap_to_click     = 1
          tap_and_drag     = 1
          drag_lock        = 1
          trackpad_natural_scrolling = 1
          warpcursor       = 1
          sloppyfocus      = 1

          # Layout (default: tile, per-tag layout rules below)
          default_mfact = 0.5
          smartgaps     = 0
          scroller_focus_center = 1
          scroller_default_proportion = 0.5
          scroller_proportion_preset  = 0.33,0.5,0.67,1.0

          tagrule=id:1,layout_name:tile
          tagrule=id:2,layout_name:tile
          tagrule=id:3,layout_name:tile
          tagrule=id:4,layout_name:tile
          tagrule=id:5,layout_name:tile
          tagrule=id:6,layout_name:tile
          tagrule=id:7,layout_name:tile
          tagrule=id:8,layout_name:tile
          tagrule=id:9,layout_name:tile

          # Reload
          bind=SUPER,r,reload_config

          # Apps
          bind=Alt,Return,spawn,${ynyDbg} focus-or-cycle --app-id org.wezfurlong.wezterm --spawn wezterm
          bind=Alt,t,spawn,${ynyDbg} focus-or-cycle --app-id org.wezfurlong.wezterm --spawn wezterm
          bind=Alt+SHIFT,t,spawn,wezterm
          bind=Alt,s,spawn,${ynyDbg} focus-or-cycle --app-id librewolf --spawn librewolf
          bind=Alt+SHIFT,s,spawn,librewolf
          bind=Alt,p,spawn,${ynyDbg} focus-or-cycle --app-id spotify --spawn spotify --summon
          bind=Alt,space,spawn,wlr-which-key

          # Close window
          bind=Alt,q,killclient

          # Fullscreen / floating
          bind=Alt,f,togglefullscreen
          bind=Alt,backslash,togglefloating

          # Focus — NEIO matching niri west/south/north/east
          bind=Alt,n,spawn,${ynyDbg} focus west
          bind=Alt,e,spawn,${ynyDbg} focus south
          bind=Alt,i,spawn,${ynyDbg} focus north
          bind=Alt,o,spawn,${ynyDbg} focus east

          # Move window
          bind=Alt+SHIFT,n,spawn,${ynyDbg} move west
          bind=Alt+SHIFT,e,spawn,${ynyDbg} move south
          bind=Alt+SHIFT,i,spawn,${ynyDbg} move north
          bind=Alt+SHIFT,o,spawn,${ynyDbg} move east

          # Resize (master factor)
          bind=Alt,minus,set_mfact,-0.05
          bind=Alt,equal,set_mfact,+0.05

          # Scroller proportion presets (mirrors niri Mod+R)
          bind=Alt,r,switch_proportion_preset

          # Switch layout
          bind=SUPER,n,switch_layout

          # Overview (mirrors niri Mod+Slash)
          bind=Alt,slash,toggleoverview

          # Workspace (tag) switching — F1-F9 matches niri
          bind=Ctrl,1,view,1,0
          bind=Ctrl,2,view,2,0
          bind=Ctrl,3,view,3,0
          bind=Ctrl,4,view,4,0
          bind=Ctrl,5,view,5,0
          bind=Ctrl,6,view,6,0
          bind=Ctrl,7,view,7,0
          bind=Ctrl,8,view,8,0
          bind=Ctrl,9,view,9,0

          # Move window to tag
          bind=Alt,1,tag,1,0
          bind=Alt,2,tag,2,0
          bind=Alt,3,tag,3,0
          bind=Alt,4,tag,4,0
          bind=Alt,5,tag,5,0
          bind=Alt,6,tag,6,0
          bind=Alt,7,tag,7,0
          bind=Alt,8,tag,8,0
          bind=Alt,9,tag,9,0

          # Mouse
          mousebind=SUPER,btn_left,moveresize,curmove
          mousebind=SUPER,btn_right,moveresize,curresize
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
