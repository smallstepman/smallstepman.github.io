{ inputs, lib, ... }: {
  den.aspects.hardware.disk.work-vm = {
    nixos = { ... }: {
      imports = [ inputs.disko.nixosModules.disko ];

      boot.initrd.availableKernelModules = [
        "ahci"
        "sr_mod"
        "uhci_hcd"
        "usb_storage"
        "usbhid"
        "virtio_blk"
        "virtio_pci"
        "virtio_scsi"
        "xhci_pci"
      ];

      disko.devices.disk.main = {
        device = lib.mkDefault "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
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
  };
}
