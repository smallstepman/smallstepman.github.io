{ den, ... }: {

  den.aspects.gpg = {
    homeManager = { ... }: {
      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        defaultCacheTtl = 31536000;
        maxCacheTtl = 31536000;
      };

      programs.git.signing.signByDefault = true;
    };
  };

}
