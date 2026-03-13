{ config, pkgs, lib, ... }:
# machines/vm-shared.nix
#
# Desktop/Wayland-specific configuration shared across VM machine definitions.
#
# NOTE: Core Linux system behavior has been migrated to den/aspects/features/linux-core.nix.
#       Secrets/sops config lives in den/aspects/features/secrets.nix.
#       Host-specific remnants (hostname, openwebui-proxy, user groups) are in
#       den/aspects/hosts/vm-aarch64.nix.
#
# What remains here (Task 8+ scope):
#   Desktop/Wayland: niri, mango, noctalia-shell, greetd, xserver, keyd
#   Desktop-adjacent: bluetooth, power-profiles-daemon, upower, fcitx5 input,
#                     wl-clipboard
#   VMware guest extras: gtkmm3, wezterm
{
  imports = [ ];

  # Noctalia prerequisites (wifi/bluetooth/power/battery integrations)
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Input method (desktop-adjacent, fcitx5 for Wayland)
  i18n.inputMethod = {
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

  # VMware guest packages (desktop-specific extras)
  # WezTerm terminal + VMware clipboard integration (gtkmm3)
  environment.systemPackages = with pkgs; [
    wl-clipboard  # Wayland clipboard
    pkgs.wezterm
    # This is needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this and seeing
    # if the clipboard still works.
    gtkmm3
  ];

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
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
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
        # - 
        # rightshift = "rightshift";  # N
        rightalt = "rightmeta";      # E
        rightcontrol = "rightalt"; # I
        rightmeta = "rightcontrol"; # O
      };
    };
  };
}
