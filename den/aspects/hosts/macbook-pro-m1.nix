{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.darwin-core
      den.aspects.darwin-desktop

        {
          homeManager = { ... }: {
            programs.git.signing.key = "9317B542250D33B34C41F62831D3B9C9754C0F5B";
            services.gpg-agent = {
              defaultCacheTtl = 1;
              maxCacheTtl = 1;
            };
          };
      }
    ];
  };
}
