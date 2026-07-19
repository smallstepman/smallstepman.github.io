{ ... }: {
  den.aspects.virtualization.qemu-guest = {
    nixos = { ... }: {
      services.qemuGuest.enable = true;
      services.spice-vdagentd.enable = true;
    };
  };
}
