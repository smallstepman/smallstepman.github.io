{ inputs, lib, overlays, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.default = {
    nixos = {
      nixpkgs.overlays = overlays;
      nixpkgs.config.allowUnfree = true;
    };

    darwin = {
      nixpkgs.overlays = overlays;
      nixpkgs.config.allowUnfree = true;
    };
  };

  # Home Manager host-level options belong on hm-host so the documented HM
  # integration context owns the OS-side wiring.
  den.ctx.hm-host.includes = [
    ({ host, ... }:
      let
        systemModule = { pkgs, ... }:
          let
            homeManagerRotateBackup = pkgs.writeShellScript "home-manager-rotate-backup" ''
              set -eu

              target_path="$1"
              backup_ext="''${HOME_MANAGER_BACKUP_EXT:-backup}"
              backup_path="$target_path.$backup_ext"
              candidate="$backup_path"
              suffix=1

              while [[ -e "$candidate" || -L "$candidate" ]]; do
                candidate="$backup_path.$suffix"
                suffix=$((suffix + 1))
              done

              exec ${pkgs.coreutils}/bin/mv "$target_path" "$candidate"
            '';
          in {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            # Rotate stale *.backup files so repeated activations stay idempotent.
            home-manager.backupCommand = homeManagerRotateBackup;
          };
      in
      (lib.optionalAttrs (host.class == "nixos") {
        nixos = systemModule;
      }) // (lib.optionalAttrs (host.class == "darwin") {
        darwin = systemModule;
      }))
  ];

  den.schema.user = { ... }: {
    config.classes = lib.mkDefault [ "homeManager" ];
  };
}
