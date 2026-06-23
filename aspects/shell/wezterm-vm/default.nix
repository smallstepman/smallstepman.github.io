{ ... }: {
  den.aspects.shell.wezterm-vm = {
    homeManager = { pkgs, ... }: {
      xdg.configFile."wezterm/wezterm.lua".text =
        builtins.readFile ./wezterm-vm.lua;
    };
  };
}
