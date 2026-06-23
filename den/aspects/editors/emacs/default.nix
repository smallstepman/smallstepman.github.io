{ inputs, ... }: {
  den.aspects.editors.emacs = {
    homeManager = { pkgs, ... }: {
      imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];

      home.packages = [ pkgs.emacs-all-the-icons-fonts ];

      programs.doom-emacs = {
        enable = true;
        doomDir = ./doom;
        emacs = pkgs.emacs-pgtk;
      };

      services.emacs = {
        enable = true;
        defaultEditor = false;
      };
    };
  };
}
