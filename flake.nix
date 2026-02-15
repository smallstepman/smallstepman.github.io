{
  description = "NixOS systems and tools by smallstepman";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Used to get ibus 1.5.29 which has some quirks we want to test.
    nixpkgs-old-ibus.url = "github:nixos/nixpkgs/e2dd4e18cc1c7314e24154331bae07df76eb582f";

    # We use the unstable nixpkgs repo for some packages.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # Master nixpkgs is used for really bleeding edge packages. Warning
    # that this is extremely unstable and shouldn't be relied on. Its
    # mostly for testing.
    nixpkgs-master.url = "github:nixos/nixpkgs";

    # Build a custom WSL installer
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # snapd
    nix-snapd.url = "github:nix-community/nix-snapd";
    nix-snapd.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      # We need to use nightly home-manager because it contains this
      # fix we need for nushell nightly:
      # https://github.com/nix-community/home-manager/commit/a69ebd97025969679de9f930958accbe39b4c705
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # I think technically you're not supposed to override the nixpkgs
    # used by neovim but recently I had failures if I didn't pin to my
    # own. We can always try to remove that anytime.
    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
    };

    # Other packages
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ghostty.url = "github:ghostty-org/ghostty";

    # Niri - scrollable-tiling Wayland compositor
    niri.url = "github:sodiboo/niri-flake";

    # LLM agents for Nix
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Mango window control for Wayland
    mangowc = {
      url = "github:DreamMaoMao/mangowc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative git repo management
    git-repo-manager = {
      url = "github:hakoerber/git-repo-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sopsidy = {
      url = "github:timewave-computer/sopsidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, home-manager, darwin, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.rust-overlay.overlays.default
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      inputs.git-repo-manager.overlays.git-repo-manager

      (final: prev:
        let
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = prev.system;
            config.allowUnfree = true;
          };
        in rec {
        # gh CLI on stable has bugs.
        gh = pkgs-unstable.gh;

        # Want the latest version of these
        claude-code = pkgs-unstable.claude-code;

        ibus = ibus_stable;
        ibus_stable = inputs.nixpkgs.legacyPackages.${prev.system}.ibus;
        ibus_1_5_29 = inputs.nixpkgs-old-ibus.legacyPackages.${prev.system}.ibus;
        ibus_1_5_31 = pkgs-unstable.ibus;
      })
    ];

    mkSystem = import ./lib/mksystem.nix {
      inherit overlays nixpkgs inputs;
    };
  in {
    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "m";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
      system = "x86_64-linux";
      user   = "m";
      wsl    = true;
    };

    darwinConfigurations.macbook-pro-m1 = mkSystem "macbook-pro-m1" {
      system = "aarch64-darwin";
      user   = "m";
      darwin = true;
    };

    # Sopsidy secret collector script (rbw/bitwarden backend)
    # Built for common host systems since collect-secrets runs locally,
    # not on the target VM.
    packages.aarch64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "aarch64-darwin"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
    packages.x86_64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "x86_64-darwin"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
    packages.aarch64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "aarch64-linux"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
    packages.x86_64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64;
      };
    };
  };
}
