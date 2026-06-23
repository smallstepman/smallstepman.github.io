{ lib, pkgs, ... }: {
  den.aspects.shell = {
    nixos = { lib, pkgs, ... }: {
      environment.pathsToLink = [ "/share/zsh" ];
      environment.localBinInPath = true;
      programs.zsh.enable = true;
      programs.nix-ld.enable = true;
      programs.nix-ld.libraries = with pkgs; [];

      home-manager.users.m.home.packages = with pkgs; [
        foot grim slurp
      ];
    };
  };
}
