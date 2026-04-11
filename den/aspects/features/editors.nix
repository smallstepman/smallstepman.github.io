{ den, lib, inputs, ... }: {

  den.aspects.editors = {
    includes = [
      ({ host, ... }:
        let
          isLinux = host.class == "nixos";
        in {
          homeManager = { pkgs, lib, ... }: {

            imports = [
              inputs.nix-doom-emacs-unstraightened.homeModule
              inputs.lazyvim.homeManagerModules.default
            ];

            home.packages = [
              pkgs.nerd-fonts.symbols-only
              pkgs.emacs-all-the-icons-fonts
            ];

            programs.doom-emacs = {
              enable = true;
              doomDir = ../../../dotfiles/common/doom;
              emacs = pkgs.emacs-pgtk;
            };

            services.emacs = {
              enable = true;
              defaultEditor = false;
            };

            programs.lazyvim = {
              enable = true;
              pluginSource = "latest";
              configFiles = ../../../dotfiles/common/lazyvim;

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

            programs.vscode = {
              enable = true;
              profiles = {
                default = {
                  extensions = import ../../../dotfiles/common/vscode/extensions.nix { inherit pkgs; };
                  keybindings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/vscode/keybindings.json);
                  userSettings = builtins.fromJSON (builtins.readFile ../../../dotfiles/common/vscode/settings.json);
                };
              };
            };

          };
        })
    ];
  };

}
