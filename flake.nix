{
  description = "NixOS systems and tools by smallstepman";

  inputs = {
    # Pin our primary nixpkgs repository. This is the main nixpkgs repository
    # we'll use for our configurations. Be very careful changing this because
    # it'll impact your entire system.
    nixpkgs.url = "github:nixos/nixpkgs/c217913993d6c6f6805c3b1a3bda5e639adfde6d";

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
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
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

    # LazyVim Nix (declarative Neovim + LazyVim)
    lazyvim.url = "github:pfassina/lazyvim-nix";

    # Non-flake sources for packages we build ourselves
    difi-src = { url = "github:oug-t/difi"; flake = false; };
    agent-of-empires-src = { url = "github:njbrake/agent-of-empires"; flake = false; };
    uniclip-src = { url = "github:quackduck/uniclip"; flake = false; };
    tmux-menus-src = { url = "github:jaclu/tmux-menus"; flake = false; };
    beads-viewer-src = { url = "github:Dicklesworthstone/beads_viewer"; flake = false; };
    aw-import-screentime-src = { url = "github:ActivityWatch/aw-import-screentime/8d6bf4a84bac840c8af577652ee70514ef3e6bc1"; flake = false; };

    # Mango window control for Wayland
    mangowc = {
      url = "github:DreamMaoMao/mangowc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia shell for Wayland
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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

    # Doom Emacs via nix-doom-emacs-unstraightened (builds Doom + deps with Nix)
    nix-doom-emacs-unstraightened = {
      url = "github:marienz/nix-doom-emacs-unstraightened";
      # Don't pull in its nixpkgs — neither the module nor overlay uses it
      inputs.nixpkgs.follows = "";
    };

  };

  outputs = { self, nixpkgs, home-manager, lazyvim, darwin, ... }@inputs: let
    # Overlays is the list of overlays we want to apply from flake inputs.
    overlays = [
      inputs.rust-overlay.overlays.default
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      inputs.git-repo-manager.overlays.git-repo-manager

      # Build non-flake packages from source
      (final: prev: {
        difi = final.buildGoModule {
          pname = "difi";
          version = "0-unstable-2026-02-17";
          src = inputs.difi-src;
          vendorHash = "sha256-bV5y8zKculYULkFl9J95qebLOzdTT/LuYycqMmHKZ+g=";
          meta.description = "Terminal-based Git diff reviewer";
        };

        agent-of-empires = final.rustPlatform.buildRustPackage {
          pname = "agent-of-empires";
          version = "0.11.2";
          src = inputs.agent-of-empires-src;
          cargoHash = "sha256-gE5FhOrBTfrn/2j7lHLrEzgYwJ6pEd5kRFY9qwgUxDY=";
          doCheck = false; # git tests need a working git in the sandbox
          nativeBuildInputs = with final; [ pkg-config cmake perl ];
          buildInputs = with final; [ openssl ];
          meta.description = "Terminal session manager for AI coding agents";
        };

        uniclip = final.buildGoModule {
          pname = "uniclip";
          version = "0-unstable";
          src = inputs.uniclip-src;
          vendorHash = "sha256-ugrWrB0YVs/oWAR3TC3bEpt1VXQC1c3oLrvFJxlR8pw=";
          patches = [ ./patches/integrations/uniclip-bind-and-env-password.patch ];
          meta.description = "Universal clipboard - copy on one device, paste on another";
        };

        wayprompt = prev.wayprompt.overrideAttrs (old: {
          patches = (old.patches or []) ++ [ ./patches/platform/wayprompt-wayland-clipboard-paste.patch ];
          nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.makeWrapper ];
          postFixup = (old.postFixup or "") + ''
            wrapProgram $out/bin/wayprompt --prefix PATH : ${final.wl-clipboard}/bin
            wrapProgram $out/bin/pinentry-wayprompt --prefix PATH : ${final.wl-clipboard}/bin
          '';
        });

        bv = final.buildGoModule {
          pname = "bv";
          version = "0-unstable-2026-02-18";
          src = inputs.beads-viewer-src;
          vendorHash = null; # uses vendored dependencies
          subPackages = [ "cmd/bv" ];
          meta.description = "Graph-aware TUI for the Beads issue tracker";
        };

        tmuxPlugins = prev.tmuxPlugins // {
          "tmux-menus" = final.tmuxPlugins.mkTmuxPlugin {
            pluginName = "tmux-menus";
            version = "0-unstable-2026-02-21";
            src = inputs.tmux-menus-src;
            rtpFilePath = "menus.tmux";
          };
        };

        opencode-dev =
          let
            pkgs-unstable = import inputs.nixpkgs-unstable {
              system = prev.system;
              config.allowUnfree = true;
            };
            src = builtins.fetchTarball {
              url = "https://github.com/anomalyco/opencode/archive/0a74fcd65dcceb1315d9e2580b97fa970f8bd154.tar.gz";
              sha256 = "0zk9m1xcy5nd9p55h9fyr0r5s9m47lpzwb2h7xkxirrxfd41gknw";
            };
            node_modules = final.callPackage (src + "/nix/node_modules.nix") {
              rev = "pr-13485";
              bun = pkgs-unstable.bun;
            };
          in
          final.callPackage (src + "/nix/opencode.nix") {
            inherit node_modules;
            bun = pkgs-unstable.bun;
          };
      })

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
