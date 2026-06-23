{ pkgs, ... }: {
  den.aspects.hardware.fonts = {
    nixos = { pkgs, ... }: {
      fonts.fontDir.enable = true;
      fonts.packages = [
        pkgs.fira-code
        pkgs.jetbrains-mono
      ];
    };
  };
}
