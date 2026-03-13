{ inputs, lib, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.schema.user = { ... }: {
    config.classes = lib.mkDefault [ "homeManager" ];
  };

  den.schema.host = { lib, ... }: {
    options.profile = lib.mkOption { type = lib.types.str; };
    options.vmware.enable = lib.mkEnableOption "VMware-specific host behavior";
    options.wsl.enable = lib.mkEnableOption "WSL behavior";
    options.graphical.enable = lib.mkEnableOption "Graphical desktop behavior";
  };
}
