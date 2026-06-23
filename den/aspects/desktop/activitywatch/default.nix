{ inputs, ... }: {
  den.aspects.activitywatch = {
    darwin = import ./_darwin.nix { inherit inputs; };

    homeManager = { ... }: {
      xdg.configFile."activitywatch/scripts" = {
        source = ./scripts;
        recursive = true;
      };
    };
  };
}
