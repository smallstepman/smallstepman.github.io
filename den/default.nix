{ inputs, lib, ... }: {
  imports = [ inputs.den.flakeModule ];

  den.schema.user = { ... }: {
    config.classes = lib.mkDefault [ "homeManager" ];
  };
}
