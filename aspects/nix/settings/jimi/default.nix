{ ... }: {
  den.aspects.nix.settings.jimi = {
    nixos = { ... }: {
      nix.settings = {
        auto-optimise-store = true;
        max-jobs = 16;
        cores = 16;
      };
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };

      time.timeZone = "UTC";
    };
  };
}
