{ ... }: {
  den.aspects.virtualization.docker = {
    nixos = { ... }: {
      virtualisation.docker.enable = true;
    };
  };
}
