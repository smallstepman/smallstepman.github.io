{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.darwin-core
      den.aspects.homebrew
      den.aspects.launchd
    ];
  };
}
