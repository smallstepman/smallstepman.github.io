{ den, lib, ... }: {

  den.aspects.devtools = {
    homeManager = { pkgs, lib, config, ... }: {

      home.packages = [
        pkgs.devenv

        pkgs.websocat
        pkgs.bws
        pkgs.yq
        pkgs.fluxcd
        pkgs.kubernetes-helm
        pkgs.tree
        pkgs.terragrunt
        pkgs.watch
        pkgs.yazi
        pkgs.btop
        pkgs.gnumake
        pkgs.just
        pkgs.dust

        pkgs.go
        pkgs.gopls

        (pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rust-analyzer" ];
          targets = [ "wasm32-wasip1" ];
        })

        (lib.hiPrio pkgs.python314)
        pkgs.uv

        pkgs.nodejs_22

        pkgs.zellij
        pkgs.kitty
        pkgs.alacritty
        pkgs.uniclip
      ];

      home.file.".gdbinit".source = ../../../dotfiles/common/gdbinit;

      xdg.configFile."tmux/menus/doomux.sh" = {
        source = ../../../dotfiles/common/tmux/doomux.sh;
        executable = true;
      };

      home.activation.installWritableTmuxMenus = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        src=${pkgs.tmuxPlugins."tmux-menus"}/share/tmux-plugins/tmux-menus
        dst="$HOME/.local/share/tmux/plugins/tmux-menus"
        run mkdir -p "$HOME/.local/share/tmux/plugins"
        run rm -rf "$dst"
        run cp -R "$src" "$dst"
        run chmod -R u+w "$dst"
      '';

      programs.tmux = {
        enable = true;
        keyMode = "vi";
        mouse = true;
        extraConfig = ''
          set -g @menus_location_x 'C'
          set -g @menus_trigger 'Space'
          set -g @menus_main_menu '${config.home.homeDirectory}/.config/tmux/menus/doomux.sh'
          set -g @menus_display_commands 'No'
          run-shell ~/.local/share/tmux/plugins/tmux-menus/menus.tmux
          set -g status-keys vi
          setw -g mode-keys vi
          set -g base-index 1
          setw -g pane-base-index 1
          set -g renumber-windows on
          set -g set-clipboard on
        '';
      };

      programs.zellij = {
        enable = true;
        settings = {
          on_force_close = "quit";
        };
      };

      programs.go = {
        enable = true;
        env = {
          GOPATH = "Documents/go";
          GOPRIVATE = [ "github.com/smallstepman" ];
        };
      };

      programs.starship = {
        enable = false;
        settings = builtins.fromTOML (builtins.readFile ../../../dotfiles/common/starship.toml);
      };

    };
  };

}
