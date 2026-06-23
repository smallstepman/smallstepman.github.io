{ pkgs, ... }: {
  services.yabai.enable = true;
  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ../../../../dotfiles/by-host/darwin/skhdrc;
  };
}
