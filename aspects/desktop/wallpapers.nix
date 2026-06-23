{ den, ... }: {
  den.aspects.desktop.wallpapers = {
    includes = [
      ({ ... }: {
        homeManager = { ... }: {
          xdg.configFile."grm/repos.yaml".source = ./grm/grm-repos.yaml;
        };
      })
    ];
  };
}
