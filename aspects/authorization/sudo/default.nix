{ config, lib, pkgs, ... }: {
  den.aspects.authorization.sudo = {
    nixos = { config, lib, ... }: {
      security.sudo.wheelNeedsPassword = true;
      security.sudo.extraConfig = ''
        Defaults timestamp_timeout=10
      '';
      security.pam.services.sudo.rules.auth."vm-touchid-bridge" = lib.mkIf
        config.virtualisation.vmware.guest.enable
        {
          order = config.security.pam.services.sudo.rules.auth.unix.order - 50;
          control = "sufficient";
          modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "seteuid"
            "/run/current-system/sw/bin/vm-touchid-sudo-bridge"
          ];
        };
    };
  };
}
