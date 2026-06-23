{ lib, inputs, ... }: {
  den.aspects.hardware.disk.jimi = {
    nixos = { ... }: {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.unattended-installer.nixosModules.diskoInstaller
      ];

      disko.devices.disk.main = {
        device = "/dev/disk/by-id/nvme-KBG40ZNV512G_KIOXIA_70KPG29NQBV1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2G";
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
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = { mountpoint = "/"; };
                  "/home" = { mountpoint = "/home"; };
                  "/nix" = { mountpoint = "/nix"; };
                  "/var" = { mountpoint = "/var"; };
                };
              };
            };
          };
        };
      };

      fileSystems."/mnt/ubuntu" = {
        device = "/dev/ubuntu-vg/ubuntu-lv";
        fsType = "ext4";
        options = [ "ro" "nofail" ];
      };
    };
  };
}
