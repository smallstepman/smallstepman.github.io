{ den, ... }: {
  den.aspects.macbook-pro-m1 = {
    includes = [
      den.aspects.darwin-core
      den.aspects.darwin-desktop
      den.aspects.macos
      den.aspects.touchid
      den.aspects.containers
      den.aspects.uniclip
      den.aspects.activitywatch
      den.aspects.nix-daemon
      den.aspects.ssh-pam
      den.aspects.shells
      den.aspects.homebrew
      den.aspects.home-manager-base
      den.aspects.opencode
      den.aspects.window-manager
      den.aspects.kanata
      den.aspects.system-defaults
      den.aspects.openwebui
      den.aspects.desktop-apps

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
