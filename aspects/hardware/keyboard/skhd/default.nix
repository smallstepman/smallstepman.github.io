{
  den.aspects.keyboard.skhd = {
    darwin = { lib, pkgs, ... }: let
      skhdPath = lib.concatStringsSep ":" [
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
    in {
      services.skhd.enable = lib.mkForce false;

      home-manager.users.m.services.skhd = {
        enable = true;
        package = pkgs.skhd;
        config = ./skhdrc;
        errorLogFile = "/tmp/skhd.err.log";
        outLogFile = "/tmp/skhd.out.log";
      };

      home-manager.users.m.launchd.agents.skhd.config.ProgramArguments = lib.mkForce [
        (lib.getExe pkgs.skhd)
        "-c"
        "/Users/m/.config/skhd/skhdrc"
        "-h"
      ];

      home-manager.users.m.launchd.agents.skhd.config.EnvironmentVariables = {
        PATH = skhdPath;
        SHELL = "/bin/bash";
      };
    };

    homeManager = { lib, pkgs, ... }: {
      home.packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.skhd ];
    };
  };
}
