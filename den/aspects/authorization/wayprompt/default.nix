{ pkgs, ... }: {
  den.aspects.authorization.wayprompt = {
    homeManager = { pkgs, ... }: {
      programs.wayprompt = {
        enable = true;
        package = pkgs.wayprompt;
      };
    };
  };
}
