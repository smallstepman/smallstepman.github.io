{ pkgs, ... }: {
  den.aspects.nix.settings = {
    nixos = { pkgs, ... }: {
      nix.package = pkgs.nixVersions.latest;
      nix.extraOptions = ''
        keep-outputs = true
        keep-derivations = true
      '';
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      nixpkgs.config.permittedInsecurePackages = [
        "mupdf-1.17.0"
      ];

      time.timeZone = "Europe/Warsaw";
      i18n.defaultLocale = "en_US.UTF-8";

      system.stateVersion = "26.05";
    };
  };
}
