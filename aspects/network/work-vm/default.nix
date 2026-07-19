{ ... }: {
  den.aspects.network.work-vm = {
    nixos = { ... }: {
      networking = {
        useDHCP = false;
        networkmanager = {
          enable = true;
          dns = "systemd-resolved";
        };
        firewall.enable = true;
      };

      services.resolved.enable = true;
    };
  };
}
