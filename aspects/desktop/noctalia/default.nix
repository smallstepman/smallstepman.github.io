{ pkgs, lib, inputs, ... }: {
  den.aspects.desktop.noctalia = {
    nixos = { ... }: {
      imports = [ inputs.noctalia.nixosModules.default ];
      programs.noctalia.enable = true;
    };

    homeManager = { pkgs, lib, config, ... }: {
      imports = [ inputs.noctalia.homeModules.default ];

      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        settings = ./noctalia.toml;
      };

      home.packages = [
        # Noctalia's git-backed plugin sources invoke git at runtime.
        pkgs.git
        (pkgs.writeShellScriptBin "noctalia-theme-reload" ''
          ${pkgs.emacs-pgtk}/bin/emacsclient -e \
            '(progn (add-to-list (quote custom-theme-load-path) "~/.local/share/noctalia/emacs-themes/") (load-theme (quote noctalia) t))' \
            2>/dev/null || true
        '')
      ];

      xdg.configFile = {
        "noctalia/user-templates.toml".source = ./noctalia-user-templates.toml;
        "noctalia/emacs-template.el".source = ./../../editors/emacs/doom/themes/noctalia-template.el;
        "noctalia/wezterm-colors-template.lua".source = ./wezterm-colors-template.lua;
        "nvim/lua/matugen-template.lua".source = ./../../editors/neovim/lazyvim/lua/matugen-template.lua;
      };

      home.activation.createNoctaliaThemeDirs =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p "$HOME/.local/share/noctalia/emacs-themes"
        '';

      # Noctalia writes Settings changes into this higher-priority state file.
      # Back up the work VM's pre-migration overrides once so they cannot mask
      # the new native v5 config; subsequent UI changes remain persistent.
      home.activation.migrateNoctaliaV5State = lib.mkIf (config.home.username == "work") (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          state_dir="$HOME/.local/state/noctalia"
          marker="$state_dir/.nix-v5-config-migrated"

          run mkdir -p "$state_dir"
          if [[ ! -e "$marker" ]]; then
            if [[ -e "$state_dir/settings.toml" ]]; then
              run mv "$state_dir/settings.toml" "$state_dir/settings.toml.pre-nix-v5"
            fi
            run touch "$marker"
          fi
        ''
      );
    };
  };
}
