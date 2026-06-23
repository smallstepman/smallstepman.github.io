{ generated, ... }: {
  den.aspects.ssh-pam = {
    darwin = import ./_darwin.nix { inherit generated; };
  };
}
