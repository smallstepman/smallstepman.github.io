{ pkgs, lib, config, inputs, ... }: {
  den.aspects.desktop.niri = {
    nixos = { pkgs, ... }: {
      imports = [ inputs.niri.nixosModules.niri ];

      environment.systemPackages = with pkgs; [
        wl-clipboard
        wezterm
        xwayland-satellite
      ];

      programs.niri.enable = true;
      programs.niri.package = pkgs.niri-unstable;
    };

    homeManager = { pkgs, lib, config, ... }:
      let
        # Upstream installs the executable as `yny` even though its package
        # metadata currently advertises `yeetnyoink` as the main program.
        yny = "${config.programs.yeetnyoink.package}/bin/yny";
        wlrWhichKey = lib.getExe pkgs.wlr-which-key;
        ynyFlags = [
          "--log-file=/tmp/yeetnyoink/debug.log"
          "--profile"
          "--log-append"
          "--config=${config.xdg.configHome}/yeetnyoink/config.toml"
        ];
        ynyArgv  = args: [ yny ] ++ ynyFlags ++ args;
      in {
        imports = [ inputs.yeetnyoink.homeManagerModules.default ];

        programs.yeetnyoink = {
          enable = true;
          # The upstream suite includes PATH and macOS fallback expectations
          # that do not hold in Nix's isolated Linux builder. The executable
          # itself is still built normally; only those environment-sensitive
          # package checks are skipped here.
          package = pkgs.yeetnyoink.overrideAttrs (_: {
            doCheck = false;
          });
          config = {
            wm.niri.enabled = true;

            app.terminal.wezterm = {
              enabled = true;
              mux_backend = "wezterm";
              host_tabs = "focus";
              focus.internal_panes.enabled = true;
              move.internal_panes.enabled = true;
              resize.internal_panes.enabled = true;
              move.docking.tear_off.enabled = true;
            };

            app.editor.neovim = {
              enabled = true;
              ui.terminal = {
                app = "wezterm";
                mux_backend = "inherit";
              };
            };

            app.editor.emacs = {
              enabled = true;
              ui.graphical.app = "emacs";
            };

            app.browser.librewolf = {
              enabled = true;
              tab_axis = "vertical";
            };
          };
        };

        programs.niri.settings = {
          hotkey-overlay.skip-at-startup = true;
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
            { geometry-corner-radius = { top-left = 12.0; top-right = 12.0; bottom-right = 12.0; bottom-left = 12.0; }; }
            { clip-to-geometry = true; }
            { matches = [ { app-id = "^librewolf$"; } ]; draw-border-with-background = false; opacity = 0.85; }
            { matches = [ { app-id = "^(brave|brave-browser|com\\.brave\\.Browser)$"; } ]; draw-border-with-background = false; opacity = 0.85; }
            { matches = [ { app-id = "^(code|Code|code-url-handler)$"; } ]; draw-border-with-background = false; opacity = 0.85; }
            { matches = [ { app-id = "^(emacs|Emacs|emacsclient|org\\.gnu\\.Emacs)$"; } ]; draw-border-with-background = false; opacity = 0.85; }
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
            focus-ring = { width = 2; active.color = "#7fc8ff"; inactive.color = "#505050"; };
          };

          workspaces = { };
          environment.NIXOS_OZONE_WL = "1";

          binds = {
            "Mod+T".action.spawn = ynyArgv [ "focus-or-cycle" "--app-id" "org.wezfurlong.wezterm" "--spawn" "wezterm" ];
            "Mod+Shift+T".action.spawn = "wezterm";
            "Mod+S".action.spawn = ynyArgv [ "focus-or-cycle" "--app-id" "librewolf" "--spawn" "librewolf" ];
            "Mod+Shift+S".action.spawn = "librewolf";
            "Mod+P".action.spawn = ynyArgv [ "focus-or-cycle" "--app-id" "spotify" "--spawn" "spotify" "--summon" ];
            "Mod+Space".action.spawn = wlrWhichKey;
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
      };
  };
}
