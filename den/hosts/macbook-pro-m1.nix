{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.activitywatch
      den.aspects.authorization
      den.aspects.containers
      den.aspects.desktop-apps
      den.aspects.keyboard.kanata
      den.aspects.keyboard.skhd
      den.aspects.network
      den.aspects.nix-daemon
      den.aspects.shell
      den.aspects.ssh-pam
      den.aspects.storage
      den.aspects.system-defaults
      den.aspects.touchid
      den.aspects.uniclip
      den.aspects.window-manager
    ];
  };
}
