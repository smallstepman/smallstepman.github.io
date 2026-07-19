{ inputs, ... }: {
  den.aspects.keyboard.kanata = {
    darwin = import ./_darwin.nix { inherit inputs; };

    nixos = { pkgs, ... }:
      let
        kanata =
          inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system}.kanata;
        configTree = builtins.path {
          path = ./.;
          name = "kanata-configs";
        };
        linuxConfig = configTree + "/config-work-vm/config.kbd";
      in {
        services.kanata = {
          enable = true;
          package = kanata;

          # The guest exposes a virtual keyboard whose /dev/input path is not
          # stable across hypervisors. With no linux-dev selector, Kanata
          # discovers and intercepts the guest keyboard automatically.
          keyboards.default.configFile = linuxConfig;
        };
      };
  };
}
