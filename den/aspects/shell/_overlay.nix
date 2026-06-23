{ inputs }: final: prev:
  let
    pkgs-unstable = import inputs.nixpkgs-unstable {
      system = prev.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  in {
    wezterm = pkgs-unstable.wezterm;
  }
