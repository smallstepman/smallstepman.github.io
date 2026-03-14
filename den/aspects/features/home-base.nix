{ den, ... }: {
  den.aspects.home-base = {
    includes = [
      ({ ... }: {
        homeManager = { ... }: {
          xdg.configFile."grm/repos.yaml".source = ../../../dotfiles/common/grm-repos.yaml;
        };
      })
    ];
  };
}
