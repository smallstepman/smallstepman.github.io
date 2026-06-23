{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.activitywatch
      den.aspects.containers
      den.aspects.desktop-apps
      den.aspects.home-manager-base
      den.aspects.homebrew
      den.aspects.keyboard.kanata
      den.aspects.keyboard.skhd
      den.aspects.nix-daemon
      den.aspects.shell
      den.aspects.ssh-pam
      den.aspects.system-defaults
      den.aspects.touchid
      den.aspects.uniclip
      den.aspects.window-manager

      den.aspects.darwin-core
      den.aspects.darwin-desktop
      den.aspects.macos
      den.aspects.opencode
      den.aspects.openwebui

        {
          homeManager = { ... }: {
            programs.git.signing.key = "9317B542250D33B34C41F62831D3B9C9754C0F5B";
            services.gpg-agent = {
              defaultCacheTtl = 1;
              maxCacheTtl = 1;
            };
          };
      }
    ];
  };
}
