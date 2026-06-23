{ den, generated, inputs, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      den.aspects.activitywatch
      den.aspects.authorization.sudo
      den.aspects.authorization.touchid.vm
      den.aspects.authorization.wayprompt
      den.aspects.desktop.browsers
      den.aspects.desktop.cursor
      den.aspects.desktop.greetd
      den.aspects.desktop.input
      den.aspects.desktop.niri
      den.aspects.desktop.noctalia
      den.aspects.desktop.power
      den.aspects.desktop.wlr-which-key
      den.aspects.devtools
      den.aspects.git.vm-signing
      den.aspects.hardware.bluetooth
      den.aspects.hardware.boot
      den.aspects.hardware.disk.vm-default
      den.aspects.hardware.fonts
      den.aspects.network.base
      den.aspects.network.kube-tunnel
      den.aspects.nix.settings
      den.aspects.secrets
      den.aspects.ssh-pam
      den.aspects.virtualization.core
      den.aspects.virtualization.flatpak
      den.aspects.vmware
      den.provides.hostname

      ({ ... }: {
        homeManager = { ... }: {
          xdg.configFile."wezterm/wezterm.lua".text =
            builtins.readFile ./../aspects/shell/wezterm-vm.lua;
        };
      })
    ];
  };
}
