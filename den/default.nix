{ inputs, lib, overlays, ... }: {
  imports = [ inputs.den.flakeModule ];

  # -------------------------------------------------------------------------
  # Host/system den wiring.
  #
  # lib/mksystem.nix used to inject overlays globally before evaluating either
  # NixOS or nix-darwin modules. den-built hosts need the same host-level
  # overlay wiring so system modules can reference custom packages like uniclip.
  #
  # The Linux-specific special-flake modules (sops-nix, nix-snapd, niri, etc.)
  # also used to be injected directly by lib/mksystem.nix. Now that den
  # assembles the nixosConfigurations, they must be wired here as host-level
  # includes too.
  # -------------------------------------------------------------------------
  den.ctx.host.includes = [
    ({ host, ... }:
      let
        systemModule = { ... }: {
          nixpkgs.overlays = overlays;
        };
      in
      (lib.optionalAttrs (host.class == "nixos") {
        nixos = systemModule;
      }) // (lib.optionalAttrs (host.class == "darwin") {
        darwin = systemModule;
      }))
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
