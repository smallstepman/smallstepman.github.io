{ config, lib, ... }: {
  den.aspects.m = {
    includes = [
      config.den.batteries.primary-user
      (config.den.batteries.user-shell "zsh")

      # Cross-platform user features
      config.den.aspects.shell
      config.den.aspects.editors.emacs
      config.den.aspects.editors.neovim
      config.den.aspects.editors.vscode
      config.den.aspects.git
      config.den.aspects.devtools
      config.den.aspects.activitywatch
      config.den.aspects.desktop-apps
      config.den.aspects.uniclip
      config.den.aspects.storage
      config.den.aspects.network
    ];
  };
}
