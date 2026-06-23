{
  den.aspects.keyboard.kanata = {
    darwin = import ./_darwin.nix;

    homeManager = { pkgs, ... }: {
      xdg.configFile = {
        "kanata-tray" = {
          source = ./tray;
          recursive = true;
        };
        "kanata" = {
          source = ./config-macbook-iso;
          recursive = true;
        };
      };
    };
  };
}
