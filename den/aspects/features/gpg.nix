{ den, ... }: {

  den.aspects.gpg = {
    homeManager = { lib, ... }: {
      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        defaultCacheTtl = lib.mkDefault 31536000;
        maxCacheTtl = lib.mkDefault 31536000;
      };

      programs.git.signing.signByDefault = true;
    };
  };

}
