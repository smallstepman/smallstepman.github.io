{ config, pkgs, lib, ... }: {
  den.aspects.hardware.nvidia = {
    nixos = { config, pkgs, lib, ... }: {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.graphics.enable = true;
      hardware.nvidia = {
        package = config.boot.kernelPackages.nvidiaPackages.stable;
        open = true;
        nvidiaSettings = false;
        nvidiaPersistenced = true;
        modesetting.enable = true;
      };
      hardware.nvidia-container-toolkit.enable = true;
      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
        daemon.settings.features.cdi = true;
        daemon.settings."log-driver" = "journald";
      };

      systemd.services.nvidia-container-toolkit-cdi-generator = {
        after = [ "nvidia-persistenced.service" "systemd-modules-load.service" ];
        wants = [ "nvidia-persistenced.service" "systemd-modules-load.service" ];
        serviceConfig.ExecStartPre = lib.mkForce [ ];
      };
      systemd.services.docker = {
        after = [ "nvidia-container-toolkit-cdi-generator.service" ];
        wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
        requires = [ "nvidia-container-toolkit-cdi-generator.service" ];
      };

      systemd.services.nvidia-power-limits = {
        description = "Set power limit for all NVIDIA GPUs (Headless)";
        after = [ "nvidia-persistenced.service" ];
        requires = [ "nvidia-persistenced.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ config.hardware.nvidia.package ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        script = ''
          echo "Setting power limit for all NVIDIA cards: 230W."
          for gpu in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
            nvidia-smi -i "$gpu" -pl 230
          done
        '';
      };
    };
  };
}
