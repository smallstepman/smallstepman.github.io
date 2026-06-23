{ inputs, ... }: {
  den.aspects.desktop-apps = {
    darwin = import ./_darwin.nix { inherit inputs; };

    homeManager = { pkgs, ... }: {
      home.packages = [ pkgs.keycastr pkgs.obsidian ];
      imports = [ inputs.mac-app-util.homeManagerModules.default ];

      home.activation.emacs-trampolines = let
        emacs = "${pkgs.emacs-pgtk}/bin/emacs";
        emacsclient = "${pkgs.emacs-pgtk}/bin/emacsclient";
      in ''
        nix run github:hraban/mac-app-util -- mktrampoline "${emacs}" /Applications/Emacs.app
        nix run github:hraban/mac-app-util -- mktrampoline "${emacsclient}" /Applications/EmacsClient.app
      '';
    };
  };
}
