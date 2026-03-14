{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.darwin-core
      den.aspects.darwin-desktop
      den.aspects.homebrew
      den.aspects.launchd

      {
        homeManager = { ... }: {
          programs.git.signing.key = "9317B542250D33B34C41F62831D3B9C9754C0F5B";
          programs.git.settings.gpg.program = "/opt/homebrew/bin/gpg";
          services.gpg-agent = {
            extraConfig = "pinentry-program /opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid";
            defaultCacheTtl = 1;
            maxCacheTtl = 1;
          };
        };
      }
    ];
  };
}
