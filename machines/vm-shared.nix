{ config, pkgs, lib, ... }:
# machines/vm-shared.nix
#
# NOTE: All desktop/Wayland/VMware configuration has been migrated to den
#       aspects as part of Task 8 of the den migration plan.
#
#   Desktop/Wayland (niri, mango, noctalia-shell, greetd, xserver, keyd,
#   bluetooth, power-profiles-daemon, upower, fcitx5, wl-clipboard, wezterm)
#   → den/aspects/features/linux-desktop.nix
#
#   VMware guest extras (gtkmm3, vmware.guest, HGFS mounts, binfmt, DHCP)
#   → den/aspects/features/vmware.nix
#
# This file is kept as a stub so the import in machines/vm-aarch64.nix
# continues to resolve; it may be removed in a future cleanup task.
{
  imports = [ ];
}
