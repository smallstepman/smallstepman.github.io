{ inputs, ... }: {
  den.aspects.activitywatch = {
    darwin = import ./_darwin.nix { inherit inputs; };
  };
}
