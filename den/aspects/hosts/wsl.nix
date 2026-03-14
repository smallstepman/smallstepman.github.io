{ den, ... }: {
  den.aspects.wsl = {
    wsl.enable = true;

    nixos = { pkgs, ... }: {
      wsl.wslConf.automount.root = "/mnt";
      wsl.startMenuLaunchers = true;

      nix.package = pkgs.nixVersions.latest;
      nix.extraOptions = ''
        keep-outputs = true
        keep-derivations = true
      '';
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      system.stateVersion = "23.05";

      environment.systemPackages = [];
    };

    homeManager = { pkgs, ... }: {
      programs.rbw.settings.pinentry = pkgs.pinentry-tty;
      programs.git.signing.key = "247AE5FC6A838272";
    };
  };
}
