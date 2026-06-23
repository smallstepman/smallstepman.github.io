{ pkgs, lib, inputs, ... }: {
  den.aspects.hardware.cooling = {
    nixos = { pkgs, lib, ... }: {
      users.users.coolercontrol = {
        isSystemUser = true;
        group = "coolercontrol";
      };
      users.groups.coolercontrol = {};

      security.sudo.extraRules = [
        {
          users = [ "coolercontrol" ];
          commands = [{
            command = "${pkgs.ipmitool}/bin/ipmitool";
            options = [ "NOPASSWD" ];
          }];
        }
      ];

      systemd.services.coolercontrold = {
        description = "CoolerControl daemon";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "coolercontrol";
          ExecStart = "${pkgs.coolercontrol.coolercontrold}/bin/coolercontrold";
          Restart = "always";
          RestartSec = 5;
        };
      };

      systemd.services.coolercontrol-gui = {
        description = "CoolerControl web UI";
        after = [ "coolercontrold.service" ];
        wants = [ "coolercontrold.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.coolercontrol.coolercontrol-gui}/bin/coolercontrol-gui";
          Restart = "always";
          RestartSec = 5;
        };
      };

      system.activationScripts.install-coolercontrol-plugins = ''
        echo "installing coolercontrol plugins..."
        mkdir -p /etc/coolercontrol/plugins/corsair-psu/ui
        cp ${inputs.corsair-psu.packages.${pkgs.system}.default}/bin/corsair-psu /etc/coolercontrol/plugins/corsair-psu/
        cp ${inputs.corsair-psu.packages.${pkgs.system}.default}/plugin-files/manifest.toml /etc/coolercontrol/plugins/corsair-psu/
        if [ -f ${inputs.corsair-psu.packages.${pkgs.system}.default}/plugin-files/ui/index.html ]; then
          cp ${inputs.corsair-psu.packages.${pkgs.system}.default}/plugin-files/ui/index.html /etc/coolercontrol/plugins/corsair-psu/ui/
        fi
        mkdir -p /etc/coolercontrol/plugins/custom-device
        cp ${inputs.ipmi-plugin.packages.${pkgs.system}.default}/bin/custom-device /etc/coolercontrol/plugins/custom-device/
        cp ${inputs.ipmi-plugin.packages.${pkgs.system}.default}/plugin-files/manifest.toml /etc/coolercontrol/plugins/custom-device/
        cp ${inputs.ipmi-plugin.packages.${pkgs.system}.default}/plugin-files/config.json /etc/coolercontrol/plugins/custom-device/
        chown -R coolercontrol:coolercontrol /etc/coolercontrol
      '';

      environment.systemPackages = [
        pkgs.coolercontrol.coolercontrol-gui
        pkgs.coolercontrol.coolercontrold
        pkgs.ipmitool
      ];
    };

    homeManager = { pkgs, ... }: {
      home.packages = [
        pkgs.coolercontrol.coolercontrol-gui
        pkgs.coolercontrol.coolercontrold
      ];
    };
  };
}
