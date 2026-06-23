{
  den.aspects.editors.vscode = {
    homeManager = { pkgs, ... }: {
      programs.vscode = {
        enable = true;
        profiles = {
          default = {
            keybindings = builtins.fromJSON (builtins.readFile ./keybindings.json);
            extensions = import ./_extensions.nix { inherit pkgs; };
          };
        };
      };
    };
  };
}
