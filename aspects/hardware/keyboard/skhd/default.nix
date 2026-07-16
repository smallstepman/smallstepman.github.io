{
  den.aspects.keyboard.skhd = {
    homeManager = { lib, pkgs, ... }: {
      home.packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.skhd-zig ];
    };
    darwin = { lib, pkgs, ... }: {
      home-manager.users.m = {
        services.skhd = {
          enable = true;
          package = pkgs.skhd-zig;
          config = ./skhdrc;
          errorLogFile = "/tmp/skhd.err.log";
          outLogFile = "/tmp/skhd.out.log";
        };
        launchd.agents.skhd.config = {
          ProgramArguments = lib.mkForce [
            (lib.getExe pkgs.skhd-zig)
            "-c"
            "/Users/m/.config/skhd/skhdrc"
            "-h"
          ];
          EnvironmentVariables = {
            PATH = lib.concatStringsSep ":" [
              "/Users/m/.nix-profile/bin"
              "/Users/m/.cargo/bin"
              "/etc/profiles/per-user/m/bin"
              "/run/current-system/sw/bin"
              "/nix/var/nix/profiles/default/bin"
              "/opt/homebrew/bin"
              "/usr/local/bin"
              "/usr/bin"
              "/bin"
              "/usr/sbin"
              "/sbin"
            ];
            SHELL = "/bin/bash";
          };
        };
      };
    };
  };
}
