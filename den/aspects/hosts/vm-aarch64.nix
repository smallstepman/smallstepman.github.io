{ den, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      den.provides.hostname
    ];
  };
}
