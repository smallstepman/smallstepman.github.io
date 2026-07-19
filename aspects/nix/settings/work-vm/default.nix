{ ... }: {
  den.aspects.nix.settings.work-vm = {
    nixos = { pkgs, ... }: {
      nix = {
        package = pkgs.nixVersions.latest;
        settings.experimental-features = [ "nix-command" "flakes" ];
      };

      time.timeZone = "Europe/Warsaw";
      i18n.defaultLocale = "en_US.UTF-8";
      system.stateVersion = "26.05";
    };
  };
}
