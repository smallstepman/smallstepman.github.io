{ lib, ... }: {
  den.aspects.storage = {
    darwin = import ./_darwin.nix;

    homeManager = { pkgs, ... }: {
      home.packages = [
        pkgs.rsync
      ];
    };
  };
}
