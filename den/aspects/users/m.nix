{ den, ... }: {
  den.aspects.m = {
    includes = [
      den.aspects.identity
      den.aspects.home-base
      den.aspects.shell
      den.aspects.git
      den.aspects.editors.emacs
      den.aspects.editors.neovim
      den.aspects.editors.vscode
      den.aspects.desktop-apps
      den.aspects.devtools
      den.aspects.ai-tools
    ];
  };
}
