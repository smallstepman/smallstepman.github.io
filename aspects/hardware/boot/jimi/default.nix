{ pkgs, lib, ... }: {
  den.aspects.hardware.boot.jimi = {
    nixos = { pkgs, ... }: {
      hardware.enableAllFirmware = true;

      boot.kernel.sysctl = {
        "kernel.panic_on_oops" = 1;
        "kernel.sysrq" = 1;
      };
      boot.zfs.forceImportRoot = false;
      boot.loader.systemd-boot.enable = lib.mkForce true;
      boot.loader.systemd-boot.configurationLimit = 20;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
      boot.loader.grub = {
        enable = lib.mkForce false;
        device = lib.mkForce "nodev";
      };

      boot.kernelPackages = pkgs.linuxPackages_6_18;
      boot.initrd.kernelModules = [ "rtw88_core" "rtw88_usb" "rtw88_88xxa" "rtw88_8821a" "rtw88_8821au" ];
    };
  };
}
