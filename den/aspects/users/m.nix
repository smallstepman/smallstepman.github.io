{ den, ... }: {
  den.aspects.m = {
    includes = [
      den.aspects.identity
      den.aspects.home-base
      den.aspects.shell
      den.aspects.git
      den.aspects.editors
      den.aspects.devtools
      den.aspects.ai-tools
    ];
  };
}
