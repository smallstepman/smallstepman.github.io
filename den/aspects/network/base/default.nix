{ config, pkgs, ... }: {
  den.aspects.network.base = {
    nixos = { config, pkgs, ... }: {
      networking.useDHCP = false;
      networking.networkmanager.enable = true;
      networking.networkmanager.dns = "systemd-resolved";
      services.resolved = {
        enable = true;
        fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
      };
      networking.firewall = {
        enable = true;
        trustedInterfaces = [ "tailscale0" "enp+" ];
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ config.services.tailscale.port ];
      };
    };
  };
}
