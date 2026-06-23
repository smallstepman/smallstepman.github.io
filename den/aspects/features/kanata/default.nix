{
  den.aspects.kanata = {
    darwin = import ./_darwin.nix;

    homeManager = { pkgs, ... }: {
      xdg.configFile = {
        "kanata-tray" = {
          source = ../../../../dotfiles/by-host/darwin/kanata/tray;
          recursive = true;
        };
        "kanata" = {
          source = ../../../../dotfiles/by-host/darwin/kanata/config-macbook-iso;
          recursive = true;
        };
      };
    };
  };
}
