{
  description = "NixOS systems and tools by smallstepman";

  inputs = {
    den.url = "github:vic/den";  # Den - aspect-oriented context-driven Nix configurations
    import-tree.url = "github:vic/import-tree"; # import-tree - import Nix modules by directory tree (required by den)
    # flake-aspects must be a direct input here because den's lib.nix accesses
    # inputs.flake-aspects.lib from the consumer flake's inputs, not den's own.
    flake-aspects.url = "github:vic/flake-aspects";

    # Unattended NixOS installer
    unattended-installer = {
      url = "github:chrillefkr/nixos-unattended-installer";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };
    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05"; # primary nixpkgs repository, changing this will impact your entire system
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable"; # We use the unstable nixpkgs repo for some packages
    nixpkgs-master.url = "github:nixos/nixpkgs"; # bleeding edge packages, this is extremely unstable and shouldn't be relied on, mostly for testing
    nix-snapd = { url = "github:nix-community/nix-snapd"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager = { url = "github:nix-community/home-manager/release-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
    darwin = { url = "github:nix-darwin/nix-darwin/nix-darwin-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
    mac-app-util.url = "github:hraban/mac-app-util";

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sopsidy = {
      url = "github:timewave-computer/sopsidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # CoolerControl plugins for jimi bare-metal server
    corsair-psu.url = "github:smallstepman/coolercontrol-plugin-corsair-ax1600i";
    ipmi-plugin.url = "github:smallstepman/coolercontrol-plugin-supermicro-h12ssli";

    # Python/uv packaging toolchain (used for APM and other uv-based Python tools)
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    #
    # Doom Emacs via nix-doom-emacs-unstraightened (builds Doom + deps with Nix). Don't pull in its nixpkgs — neither the module nor overlay uses it
    nix-doom-emacs-unstraightened = { url = "github:marienz/nix-doom-emacs-unstraightened"; inputs.nixpkgs.follows = ""; };
    git-repo-manager = { url = "github:hakoerber/git-repo-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    lazyvim.url = "github:pfassina/lazyvim-nix"; # LazyVim Nix (declarative Neovim + LazyVim)
    llm-agents.url = "github:numtide/llm-agents.nix";
    niri.url = "github:sodiboo/niri-flake";
    noctalia = { url = "github:noctalia-dev/noctalia-shell"; inputs.nixpkgs.follows = "nixpkgs-unstable"; };
    rbw.url = "github:smallstepman/rbw"; # rbw (Bitwarden CLI) with inject/run support
    rust-overlay = { url = "github:oxalica/rust-overlay"; inputs.nixpkgs.follows = "nixpkgs"; };
    sonar.url = "github:smallstepman/sonar";
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
    # ── Overlays ─────────────────────────────────────────────────────────
    overlays = [
      inputs.rust-overlay.overlays.default
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.default
      inputs.git-repo-manager.overlays.git-repo-manager
      inputs.yeetnyoink.overlays.default

      (final: prev: {
        rbw = inputs.rbw.packages.${prev.stdenv.hostPlatform.system}.default;
      })
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
      let
        osModule = {
          nixpkgs.overlays = overlays;
          nixpkgs.config.allowUnfree = true;
        };
      in {
        imports = [ inputs.den.flakeModule ];

        den.default = { nixos = osModule; darwin = osModule; };

        den.schema.hm-host.includes = [
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

        den.schema.user = { ... }: {
          config.classes = lib.mkDefault [ "homeManager" ];
        };
      };

    # ── Den evaluation ───────────────────────────────────────────────────
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
