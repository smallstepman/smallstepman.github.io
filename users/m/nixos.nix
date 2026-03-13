{ pkgs, lib, ... }:
# users/m/nixos.nix
#
# NixOS system-level configuration for user m.
#
# NOTE: Most settings have been migrated to den aspects (Task 7):
#   - environment.localBinInPath, programs.zsh.enable, programs.nix-ld.*,
#     environment.pathsToLink → den/aspects/features/linux-core.nix
#   - systemd.user.services.rbw-config, users.users.m.hashedPasswordFile
#     → den/aspects/features/secrets.nix
#   - users.users.m.extraGroups, users.users.m.openssh.authorizedKeys
#     → den/aspects/hosts/vm-aarch64.nix
#
# What remains: base user definition (isNormalUser, home, shell).
# The shell setting is kept here so the legacy import-tree still works
# for non-den consumers; den sets shell via den.provides.user-shell.

{
  users.users.m = {
    isNormalUser = true;
    home = "/home/m";
    shell = pkgs.zsh;
  };
}
