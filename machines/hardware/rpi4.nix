{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # RPI4 specific settings
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  
  # Kernel parameters for RPI4
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
  ];
  
  # Enable GPU memory split for headless (minimal)
  boot.loader.raspberryPi.firmwareConfig = ''
    gpu_mem=16
  '';

  # Filesystems needed for USB drives
  boot.supportedFilesystems = [
    "btrfs"
    "ext4"
    "vfat"
    "exfat"
    "ntfs"
    "xfs"
  ];

  # Load kernel modules for USB storage
  boot.kernelModules = [ "usb-storage" "uas" ];

  # Networking
  networking.useDHCP = lib.mkDefault true;
  
  # Enable SSH for headless setup (key auth only, following vm.sh pattern)
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;

  # Firmware for RPI4
  hardware.enableRedistributableFirmware = true;
  
  system.stateVersion = "25.11";
}
