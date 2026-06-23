{ den, lib, inputs, ... }: {
  den.aspects.jimi = {
    includes = [
      den.aspects.hardware.boot.jimi
      den.aspects.hardware.disk.jimi
      den.aspects.hardware.nvidia
      den.aspects.hardware.nvidia.gpu-monitoring
      den.aspects.hardware.cooling
      den.aspects.monitoring
      den.aspects.network.tailscale
      den.aspects.ssh-pam.jimi
      den.aspects.nix.settings.jimi
      den.aspects.services.vllm
      den.aspects.shell
      den.aspects.devtools
      den.provides.hostname

      ({ host, ... }: {
        nixos = { config, pkgs, lib, ... }: {
          networking.hostName = "jimi";
          networking.networkmanager.enable = true;
          networking.networkmanager.ensureProfiles.profiles."Preconfigured-WiFi" = {
            connection = { id = "Siema"; type = "wifi"; autoconnect = true; };
            wifi = { ssid = "Siema"; mode = "infrastructure"; };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "p79sqKgG2DyRlh";
            };
          };

          users.users.root = {
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
            ];
            hashedPassword = "$6$fhySpewi.hTKt.1D$nfheFtKH358q9dKSgrHGsgfzIsot4MgHQiT/A4YMB3hLe00CxTiiGr94qJZGsmFMOIbVMxqGq5emtrWJFWEwD1";
          };

          security.sudo.wheelNeedsPassword = false;

          system.stateVersion = "26.05";
        };
      })
    ];
  };
}
