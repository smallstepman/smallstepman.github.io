{
  den.aspects.keyboard.skhd = {
    darwin = { pkgs, ... }: {
      services.skhd = {
        enable = true;
        package = pkgs.skhd;
        skhdConfig = builtins.readFile ./skhdrc;
      };
    };

    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.skhd ];
    };
  };
}
