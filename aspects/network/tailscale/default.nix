{ ... }: {
  den.aspects.network.tailscale = {
    nixos = { ... }: {
      services.tailscale = {
        enable = true;
        useRoutingFeatures = "both";
        extraUpFlags = [ "--advertise-exit-node" ];
      };
    };
  };
}
