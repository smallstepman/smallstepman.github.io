{ config, pkgs, lib, ... }: {
  # machines/vm-aarch64.nix
  #
  # Hardware wiring for the vm-aarch64 (vm-macbook) NixOS machine.
  #
# VMware guest tools, HGFS mounts, and nixpkgs VM config have been migrated to
# den/aspects/features/vmware.nix.
# aarch64-specific binfmt and the enp2s0 DHCP pin live in
# den/aspects/hosts/vm-aarch64.nix.
# Desktop/Wayland stack has been migrated to den/aspects/features/linux-desktop.nix.
  imports = [
    ./hardware/vm-aarch64.nix
    ./hardware/disko-vm.nix
    ./vm-shared.nix
  ];
}
