{ inputs, lib, overlays, ... }: {
  imports = [ inputs.den.flakeModule ];

  # -------------------------------------------------------------------------
  # Linux/NixOS module imports for the den host context.
  #
  # These are the special-flake modules (sops-nix, nix-snapd, niri, etc.) that
  # lib/mksystem.nix used to inject directly.  Now that den assembles the
  # nixosConfigurations, they must be wired here as host-level includes.
  # -------------------------------------------------------------------------
  den.ctx.host.includes = [
    ({ host, ... }:
      let isLinux = host.class == "nixos"; isWSL = host.wsl.enable or false;
      in lib.optionalAttrs isLinux {
        nixos.imports = [
          inputs.sops-nix.nixosModules.sops
          inputs.sopsidy.nixosModules.default
          inputs.nix-snapd.nixosModules.default
          inputs.niri.nixosModules.niri
          inputs.disko.nixosModules.disko
          inputs.mangowc.nixosModules.mango
          inputs.noctalia.nixosModules.default
        ] ++ lib.optionals isWSL [
          inputs.nixos-wsl.nixosModules.wsl
        ];
      })
  ];

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
