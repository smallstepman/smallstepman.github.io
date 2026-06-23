{ pkgs, ... }: {
  den.aspects.desktop.wlr-which-key = {
    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.wlr-which-key ];

      xdg.configFile."wlr-which-key/config.yaml".text =
        builtins.readFile ./wlr-which-key-config.yaml;
    };
  };
}
