{ pkgs, lib, inputs, ... }: {
  den.aspects.desktop.noctalia = {
    nixos = { ... }: {
      imports = [ inputs.noctalia.nixosModules.default ];
      programs.noctalia.enable = true;
    };

    homeManager = { pkgs, lib, ... }: {
      imports = [ inputs.noctalia.homeModules.default ];

      programs.noctalia = {
        enable = true;
        settings = ./noctalia.json;
      };

      home.packages = [
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
    };
  };
}
