{ lib, ... }:

{
  services.greetd.enable = lib.mkForce false;
  services.xserver.enable = lib.mkForce false;
  programs.niri.enable = lib.mkForce false;
  programs.mango.enable = lib.mkForce false;
  services.noctalia-shell.enable = lib.mkForce false;
  services.flatpak.enable = lib.mkForce false;
  services.snap.enable = lib.mkForce false;
}
