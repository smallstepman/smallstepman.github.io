{ inputs, ... }: {
  den.aspects.virtualization.flatpak = {
    nixos = { ... }: {
      imports = [ inputs.nix-snapd.nixosModules.default ];
      services.flatpak.enable = true;
      services.snap.enable = true;
    };
  };
}
