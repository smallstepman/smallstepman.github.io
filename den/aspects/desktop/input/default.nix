{ pkgs, ... }: {
  den.aspects.desktop.input = {
    nixos = { pkgs, ... }: {
      i18n.inputMethod = {
        enable = true;
        type = "fcitx5";
        fcitx5.addons = with pkgs; [
          qt6Packages.fcitx5-chinese-addons
          fcitx5-gtk
          fcitx5-hangul
          fcitx5-mozc
        ];
        fcitx5.waylandFrontend = true;
      };

      services.xserver.xkb.layout = "us";

      services.keyd = {
        enable = true;
        keyboards.default = {
          ids = [ "*" ];
          settings.main = {
            leftmeta    = "leftcontrol";
            leftcontrol = "leftalt";
            leftalt     = "leftmeta";
            rightalt    = "rightmeta";
            rightcontrol = "rightalt";
            rightmeta   = "rightcontrol";
          };
        };
      };
    };
  };
}
