{ inputs, lib, overlays, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.ctx.user.includes = [
    ({ ... }: {
      homeManager = { ... }: {
        nixpkgs.overlays = overlays;
        nixpkgs.config.allowUnfree = true;
      };
    })
  ];

  den.schema.user = { ... }: {
    config.classes = lib.mkDefault [ "homeManager" ];
  };

  den.schema.host = { lib, ... }: {
    options.profile = lib.mkOption {
      type = lib.types.str;
      description = "Host configuration profile name, used to select the NixOS configuration for this host.";
      example = "vm";
    };
    options.vmware.enable = lib.mkEnableOption "VMware-specific host behavior";
    options.graphical.enable = lib.mkEnableOption "Graphical desktop behavior";
  };
}
