{ config, pkgs, ... }:

{
  # Noctalia prerequisites (wifi/bluetooth/power/battery integrations)
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Select internationalisation properties.
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-gtk
        fcitx5-hangul
        fcitx5-mozc
      ];
      # Use Wayland input method frontend instead of GTK_IM_MODULE
      # See: https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland
      fcitx5.waylandFrontend = true;
    };
  };

  # Enable niri (scrollable-tiling Wayland compositor)
  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };

  # Enable Noctalia shell service for Wayland sessions
  services.noctalia-shell.enable = true;

  # Enable mango (Wayland compositor) - configured via home-manager
  programs.mango.enable = true;

  # greetd with tuigreet (minimal, stable, respects environment)
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # Keep xserver for XWayland support
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";

  # Modifier remap via keyd
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        leftmeta = "leftcontrol";   # A
        leftcontrol = "leftalt";   # R
        leftalt = "leftmeta";        # S
        # leftshift = "leftshift";    # T
        #
        # rightshift = "rightshift";  # N
        rightalt = "rightmeta";      # E
        rightcontrol = "rightalt"; # I
        rightmeta = "rightcontrol"; # O
      };
    };
  };

  # escape hatches
  services.flatpak.enable = true;
  services.snap.enable = true;
}
