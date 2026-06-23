{ inputs, ... }: {
  den.aspects.editors.neovim = {
    homeManager = { pkgs, lib, ... }: {
      imports = [ inputs.lazyvim.homeManagerModules.default ];

      home.packages = [ pkgs.nerd-fonts.symbols-only ];

      programs.lazyvim = {
        enable = true;
        pluginSource = "latest";
        configFiles = ./lazyvim;

        extras = {
          lang.nix.enable = true;
          lang.python = {
            enable = true;
            installDependencies = true;
            installRuntimeDependencies = true;
          };
          lang.go = {
            enable = true;
            installDependencies = true;
            installRuntimeDependencies = true;
          };
          lang.typescript = {
            enable = true;
            installDependencies = false;
            installRuntimeDependencies = true;
          };
          lang.rust.enable = true;
          ai.copilot.enable = true;
        };

        extraPackages = with pkgs; [
          nixd
          alejandra
          pyright
        ];
      };
    };
  };
}
