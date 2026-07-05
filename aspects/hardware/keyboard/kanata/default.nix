{ inputs, ... }: {
  den.aspects.keyboard.kanata = {
    darwin = import ./_darwin.nix { inherit inputs; };
  };
}
