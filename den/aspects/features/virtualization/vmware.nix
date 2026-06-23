{ den, ... }: {
  den.aspects.vmware = {
    nixos = { pkgs, ... }: {
      virtualisation.vmware.guest.enable = true;
      environment.systemPackages = [ pkgs.gtkmm3 ];
    };
  };
}
