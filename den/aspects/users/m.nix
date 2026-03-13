{ den, ... }: {
  den.aspects.m = {
    includes = [
      den.aspects.identity
      den.aspects.shell-git
      den.aspects.gpg
      den.aspects.editors-devtools
      den.aspects.ai-tools
    ];
  };
}
