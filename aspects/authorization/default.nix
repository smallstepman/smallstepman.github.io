{ generated, ... }: {
  den.aspects.authorization = {
    darwin = import ./_pam.nix { inherit generated; };
  };
}
