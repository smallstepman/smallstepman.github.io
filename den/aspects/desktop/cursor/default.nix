{ pkgs, ... }: {
  den.aspects.desktop.cursor = {
    homeManager = { pkgs, ... }: {
      home.pointerCursor = {
        name = "Vanilla-DMZ";
        package = pkgs.vanilla-dmz;
        size = 128;
      };
    };
  };
}
