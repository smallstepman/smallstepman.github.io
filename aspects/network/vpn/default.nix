{ lib, ... }: {
  den.aspects.network = {
    darwin = import ./_darwin.nix;

    homeManager = { pkgs, ... }: {
      home.packages = [
        pkgs.sshpass
      ];
    };
  };
}
