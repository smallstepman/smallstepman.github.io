{ den, ... }: {
  den.aspects.s = {
    includes = [
      den.aspects.shell
      den.aspects.devtools
      den.aspects.ai-tools
    ];
  };
}
