{ den, lib, ... }: {
  den.aspects.home-base = {
    includes = [
      ({ host, ... }:
        let
          isDarwin = host.class == "darwin";
          isLinux = host.class == "nixos";
        in {
          homeManager = { pkgs, lib, ... }: {
            home.packages = lib.optionals isDarwin [
              pkgs.ghostty-bin
              pkgs.skhd
              pkgs.cachix
              pkgs.gettext
              pkgs.sentry-cli
              pkgs.rsync
              pkgs.sshpass
            ];

            xdg.configFile = {
              "grm/repos.yaml".source = ../../../dotfiles/common/grm-repos.yaml;
            } // (lib.optionalAttrs isDarwin {
              "wezterm/wezterm.lua".text = builtins.readFile ../../../dotfiles/by-host/darwin/wezterm.lua;
              "activitywatch/scripts" = {
                source = ../../../dotfiles/by-host/darwin/activitywatch;
                recursive = true;
              };
              "kanata-tray" = {
                source = ../../../dotfiles/by-host/darwin/kanata/tray;
                recursive = true;
              };
              "kanata" = {
                source = ../../../dotfiles/by-host/darwin/kanata/config-macbook-iso;
                recursive = true;
              };
            });

            programs.rbw = lib.mkIf isLinux {
              enable = true;
              settings = {
                base_url = "https://api.bitwarden.eu";
                email = "overwritten-by-systemd";
                lock_timeout = 86400;
              };
            };
          };
        })
    ];
  };
}
