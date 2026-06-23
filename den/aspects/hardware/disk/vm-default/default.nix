{ config, lib, pkgs, inputs, generated, ... }: {
  den.aspects.hardware.disk.vm-default = {
    nixos = { config, lib, pkgs, ... }: {
      imports = [ inputs.disko.nixosModules.disko ];

      boot.initrd.availableKernelModules = [ "uhci_hcd" "ahci" "xhci_pci" "nvme" "usbhid" "sr_mod" ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];
      swapDevices = [ ];

      disko.devices = {
        disk.main = {
          device = lib.mkDefault "/dev/nvme0n1";
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "500M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };

      boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

      fileSystems."/nixos-config" = {
        fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
        device = ".host:/nixos-config";
        options = [ "umask=22" "uid=1000" "gid=1000" "allow_other" "auto_unmount" "defaults" ];
      };

      fileSystems."/nixos-generated" = {
        fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
        device = ".host:/nixos-generated";
        options = [ "umask=22" "uid=1000" "gid=1000" "allow_other" "auto_unmount" "defaults" ];
      };

      fileSystems."/Users/m/Projects" = {
        fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
        device = ".host:/Projects";
        options = [ "umask=22" "uid=1000" "gid=1000" "allow_other" "auto_unmount" "defaults" ];
      };

      networking.interfaces.enp2s0.useDHCP = true;

      sops.hostPubKey = lib.removeSuffix "\n"
        (generated.readFile "vm-age-pubkey");

      networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];
    };
  };
}
