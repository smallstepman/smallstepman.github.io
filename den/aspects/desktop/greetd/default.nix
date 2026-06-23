{ config, pkgs, ... }: {
  den.aspects.desktop.greetd = {
    nixos = { config, pkgs, ... }: {
      services.xserver.enable = true;
      services.xserver.windowManager.i3.enable = true;

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions --xsessions ${config.services.displayManager.sessionData.desktops}/share/xsessions";
            user = "greeter";
          };
        };
      };
    };
  };
}
