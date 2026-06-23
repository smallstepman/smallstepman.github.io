{ ... }: {
  den.aspects.virtualization.core = {
    nixos = { ... }: {
      virtualisation.docker.enable = false;
    };
  };
}
