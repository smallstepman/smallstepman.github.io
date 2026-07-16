{
  description = "NixOS systems and tools by smallstepman";

  inputs = {
    den.url = "github:vic/den"; # aspect-oriented context-driven Nix configurations
    import-tree.url = "github:vic/import-tree"; # import-tree - import Nix modules by directory tree 
    flake-aspects.url = "github:vic/flake-aspects"; # flake-aspects must be a direct input here because den's lib.nix accesses inputs.flake-aspects.lib from the consumer flake's inputs, not den's own.

    unattended-installer = { # Unattended NixOS installer
      url = "github:chrillefkr/nixos-unattended-installer";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };
    disko = { # Declarative disk partitioning
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05"; # primary nixpkgs repository, changing this will impact entire system
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable"; # use the unstable for some packages
    nixpkgs-master.url = "github:nixos/nixpkgs"; # bleeding edge packages, very unstable, shouldn't be relied on, mostly for testing
    home-manager = { url = "github:nix-community/home-manager/release-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
    nur.url = "github:nix-community/NUR";
    darwin = { url = "github:nix-darwin/nix-darwin/nix-darwin-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
    mac-app-util.url = "github:hraban/mac-app-util";
    nix-snapd = { url = "github:nix-community/nix-snapd"; inputs.nixpkgs.follows = "nixpkgs"; };

    # Secrets management
    sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    sopsidy = { url = "github:timewave-computer/sopsidy"; inputs.nixpkgs.follows = "nixpkgs"; };
    # CoolerControl plugins for jimi bare-metal server
    corsair-psu.url = "github:smallstepman/coolercontrol-plugin-corsair-ax1600i";
    ipmi-plugin.url = "github:smallstepman/coolercontrol-plugin-supermicro-h12ssli";

    git-repo-manager = { url = "github:hakoerber/git-repo-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    herdr.url = "github:ogulcancelik/herdr";
    kanata-tray = { url = "github:rszyma/kanata-tray"; inputs.nixpkgs.follows = "nixpkgs-unstable"; };
    lazyvim.url = "github:pfassina/lazyvim-nix"; 
    llm-agents.url = "github:numtide/llm-agents.nix";
    niri.url = "github:sodiboo/niri-flake";
    nix-doom-emacs-unstraightened = { url = "github:marienz/nix-doom-emacs-unstraightened"; inputs.nixpkgs.follows = ""; }; # don't pull in its nixpkgs — neither the module nor overlay uses it
    noctalia = { url = "github:noctalia-dev/noctalia-shell"; inputs.nixpkgs.follows = "nixpkgs-unstable"; };
    rbw.url = "github:smallstepman/rbw"; # rbw (Bitwarden CLI) with inject/run support
    rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
    yeetnyoink.url = "github:smallstepman/yeetnyoink"; # yeetnyoink - window/app focus orchestrator

    # Non-flake sources for packages we build ourselves
    aw-import-screentime-src = { url = "github:ActivityWatch/aw-import-screentime/8d6bf4a84bac840c8af577652ee70514ef3e6bc1"; flake = false; };
    uniclip-src = { url = "github:quackduck/uniclip"; flake = false; };
    glowm-src = { url = "github:atani/glowm"; flake = false; };
    btop-src = { url = "github:aristocratos/btop"; flake = false; };
    tmux-menus-src = { url = "github:jaclu/tmux-menus"; flake = false; };
  };
  outputs = { self, nixpkgs, ... }@inputs:
  let
    overlays = [
      inputs.nur.overlays.default
      inputs.llm-agents.overlays.shared-nixpkgs
      (final: prev:
        let
          system = prev.stdenv.hostPlatform.system;
          rolldownBinding = {
            aarch64-darwin = "@rolldown/binding-darwin-arm64";
            x86_64-darwin = "@rolldown/binding-darwin-x64";
            aarch64-linux = "@rolldown/binding-linux-arm64-gnu";
            x86_64-linux = "@rolldown/binding-linux-x64-gnu";
          }.${system} or null;
          patchCodexAcpLock = ''
            ${prev.nodejs}/bin/node <<'NODE'
            const fs = require("fs");
            const lockPath = "package-lock.json";
            const keep = process.env.ROLLDOWN_BINDING;
            const lock = JSON.parse(fs.readFileSync(lockPath, "utf8"));
            const rolldown = lock.packages["node_modules/rolldown"];

            if (!rolldown?.optionalDependencies?.[keep]) {
              throw new Error("missing expected rolldown binding " + keep);
            }

            for (const name of Object.keys(rolldown.optionalDependencies)) {
              if (name.startsWith("@rolldown/binding-") && name !== keep) {
                delete rolldown.optionalDependencies[name];
              }
            }

            for (const path of Object.keys(lock.packages)) {
              if (path.startsWith("node_modules/@rolldown/binding-") && path !== "node_modules/" + keep) {
                delete lock.packages[path];
              }
            }

            fs.writeFileSync(lockPath, JSON.stringify(lock, null, 2) + "\n");
            NODE
          '';
        in
        prev.lib.optionalAttrs (rolldownBinding != null) {
          llm-agents = prev.llm-agents // {
            codex-acp = prev.llm-agents.codex-acp.overrideAttrs (old: {
              postPatch = (old.postPatch or "") + patchCodexAcpLock;
              npmDepsHash = "sha256-YD6e+M5EchYBFqF+d1nPD0e4tfooDwCm8I6v5yTs8tY=";
              npmDeps = prev.fetchNpmDeps {
                inherit (old) src;
                name = "${old.pname}-${old.version}-npm-deps";
                hash = "sha256-YD6e+M5EchYBFqF+d1nPD0e4tfooDwCm8I6v5yTs8tY=";
                fetcherVersion = old.npmDepsFetcherVersion;
                postPatch = (old.postPatch or "") + patchCodexAcpLock;
                ROLLDOWN_BINDING = rolldownBinding;
              };
              ROLLDOWN_BINDING = rolldownBinding;
            });
          };
        })
      inputs.herdr.overlays.default
      inputs.rust-overlay.overlays.default
      inputs.niri.overlays.niri
      inputs.git-repo-manager.overlays.git-repo-manager
      inputs.yeetnyoink.overlays.default
      (final: prev: { rbw = inputs.rbw.packages.${prev.stdenv.hostPlatform.system}.default; })
      (final: prev: { skhd-zig = final.callPackage (import ./aspects/hardware/keyboard/skhd/_pkg.skhd-zig.nix).package { }; })
    ] ++ map (f: import f { inherit inputs; }) [
      ./aspects/clipboard/_overlay.nix
      ./aspects/devtools/_overlay.nix
      ./aspects/shell/tmux/_overlay.nix
      ./aspects/shell/_overlay.nix
      ./aspects/authorization/wayprompt/_overlay.nix
    ];

    mkPackages = flake:
      let systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      in builtins.listToAttrs (map (system: {
        name = system;
        value.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
          pkgs = import nixpkgs { inherit system; };
          hosts = { inherit (flake.nixosConfigurations) vm-aarch64; };
        };
      }) systems);

    mkGenerated = gen:
      let
        requireFile = relative:
          let path = if gen == null then null else gen + "/${relative}";
          in if path != null && builtins.pathExists path then path
          else throw ''
            Missing generated input file `${relative}`.
            Create a wrapper flake with `scripts/external-input-flake.sh`
            or call `lib.mkOutputs { generated = <path>; }`.
            Supported default locations are `~/.local/share/nix-config-generated` on macOS
            and `/nixos-generated` inside the VMware guest.
          '';
      in {
        root = gen;
        inherit requireFile;
        readFile = relative: builtins.readFile (requireFile relative);
      };

    denModule = { inputs, lib, overlays, ... }:
      let osModule = {
        nixpkgs.overlays = overlays;
        nixpkgs.config.allowUnfree = true;
      };
      in {
        imports = [ inputs.den.flakeModule ];
        den = {
          default = { nixos = osModule; darwin = osModule; };
          schema = {
            user.classes = lib.mkDefault [ "homeManager" ];
            hm-host.includes = [
              ({ user, ... }:
                let
                  host = user.host;
                  systemModule = { pkgs, ... }: {
                    home-manager.useGlobalPkgs = true;
                    home-manager.useUserPackages = true;
                    home-manager.backupFileExtension = "backup";
                    home-manager.users.m.home.stateVersion = "18.09";
                    home-manager.users.m.home.enableNixpkgsReleaseCheck = false;
                    home-manager.backupCommand = ''
                      set -eu
                      for ((s=1; ; s++)); do [[ -e "$1.backup.$s" || -L "$1.backup.$s" ]] || break; done
                      exec ${pkgs.coreutils}/bin/mv "$1" "$1.backup.$s"
                    '';
                  };
                in
                lib.optionalAttrs (builtins.elem host.class [ "nixos" "darwin" ]) {
                  ${host.class} = systemModule;
                })
            ];
          };
        };
      };

    mkDen = { generated }: (nixpkgs.lib.evalModules {
      modules = [ denModule ./hosts.nix (inputs.import-tree ./aspects) ];
      specialArgs = { inherit generated inputs overlays; };
    }).config;

    den = mkDen { generated = mkGenerated inputs.generated; };

    mkOutputs = { generated }:
      let den' = mkDen { generated = mkGenerated generated; };
      in den'.flake // { packages = mkPackages den'.flake; };

  in {
    lib.mkOutputs = mkOutputs;
    inherit (den.flake) nixosConfigurations darwinConfigurations;
    packages = mkPackages den.flake;
  };
}
