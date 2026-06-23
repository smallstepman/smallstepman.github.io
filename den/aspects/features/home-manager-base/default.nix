{
  den.aspects.home-manager-base = {
    homeManager = { pkgs, ... }: {
      home.packages = [
        pkgs.ghostty-bin pkgs.skhd pkgs.cachix pkgs.gettext
        pkgs.sentry-cli pkgs.rsync pkgs.sshpass pkgs.keycastr
      ];

      xdg.configFile = {
        "wezterm/wezterm.lua".text =
          builtins.readFile ../../../../dotfiles/by-host/darwin/wezterm.lua;
        "activitywatch/scripts" = {
          source = ../../../../dotfiles/by-host/darwin/activitywatch;
          recursive = true;
        };
      };
    };
  };
}
