{ inputs }:
let
  nixpkgs = inputs.nixpkgs;

  # Overlays is the list of overlays we want to apply from flake inputs.
  overlays = [
    inputs.rust-overlay.overlays.default
    inputs.niri.overlays.niri
    inputs.llm-agents.overlays.default
    inputs.git-repo-manager.overlays.git-repo-manager
    inputs.yeetnyoink.overlays.default

    # Build non-flake packages from source
    (final: prev: {
      rbw = inputs.rbw.packages.${prev.stdenv.hostPlatform.system}.default;

      uniclip = final.buildGoModule {
        pname = "uniclip";
        version = "0-unstable";
        src = inputs.uniclip-src;
        vendorHash = "sha256-ugrWrB0YVs/oWAR3TC3bEpt1VXQC1c3oLrvFJxlR8pw=";
        patches = [ ../patches/uniclip-bind-and-env-password.patch ];
        meta.description = "Universal clipboard - copy on one device, paste on another";
      };

      glowm = final.buildGo126Module {
        pname = "glowm";
        version = "0-unstable";
        src = inputs.glowm-src;
        vendorHash = "sha256-4HfoWsywmWTzmv33ZScyrqmpZDf4A9EESYsYdtmbLC0=";
        subPackages = [ "cmd/glowm" ];

        meta = {
          description = "Glow-like Markdown CLI with Mermaid rendering";
          homepage = "https://github.com/atani/glowm";
          license = final.lib.licenses.mit;
          mainProgram = "glowm";
        };
      };

      btop = prev.btop.overrideAttrs (_: {
        version = "1.4.7";
        src = inputs.btop-src;

        nativeBuildInputs = [
          final.gnumake
          final.gcc14
          final.coreutils
          final.gnused
          final.lowdown
        ] ++ final.lib.optionals final.stdenv.hostPlatform.isLinux [
          final.autoAddDriverRunpath
        ];

        buildInputs = final.lib.optionals final.stdenv.hostPlatform.isDarwin [
          final.apple-sdk_15
        ];

        dontUseCmakeConfigure = true;
        makeFlags = [ "PREFIX=$(out)" "GPU_SUPPORT=true" ];

        buildPhase = ''
          runHook preBuild
          make btop
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          make install PREFIX=$out
          runHook postInstall
        '';

        versionCheckProgram = "${placeholder "out"}/bin/btop";
        versionCheckProgramArg = "--version";
        nativeInstallCheckInputs = [ final.versionCheckHook ];
        doInstallCheck = true;
      });

      bws = prev.bws.overrideAttrs (finalAttrs:
        let
          version = "2.0.0";
          src = final.fetchFromGitHub {
            owner = "bitwarden";
            repo = "sdk";
            rev = "bws-v${version}";
            hash = "sha256-NjnLoa4UjPzTejjEwc5LIrHqeqncXoMICJM2eUesoIM=";
          };
        in {
          inherit version;
          inherit src;
          cargoDeps = final.rustPlatform.fetchCargoVendor {
            inherit src;
            name = "${finalAttrs.pname}-${version}";
            hash = "sha256-lfnCUWf9MM1Yynxza7Fz1qxNyDbPNMOcbVHkvZx32bk=";
          };
        });

      wayprompt = prev.wayprompt.overrideAttrs (old: {
        patches = (old.patches or []) ++ [ ../patches/wayprompt-wayland-clipboard-paste.patch ];
        nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.makeWrapper ];
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/wayprompt --prefix PATH : ${final.wl-clipboard}/bin
          wrapProgram $out/bin/pinentry-wayprompt --prefix PATH : ${final.wl-clipboard}/bin
        '';
      });

      };

      tmuxPlugins = prev.tmuxPlugins // {
        "tmux-menus" = final.tmuxPlugins.mkTmuxPlugin {
          pluginName = "tmux-menus";
          version = "0-unstable-2026-02-21";
          src = inputs.tmux-menus-src;
          rtpFilePath = "menus.tmux";
        };
      };
    })

    (final: prev:
      let
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = prev.stdenv.hostPlatform.system;
          config.allowUnfree = true;
        };
      in rec {
      # Want the latest version of these
      wezterm = pkgs-unstable.wezterm;
    })
  ];

  generated =
    let
      requireFile = relative:
        let
          path =
            if inputs.generated == null then
              null
            else
              inputs.generated + "/${relative}";
        in
          if path != null && builtins.pathExists path then
            path
          else
            throw ''
              Missing generated input file `${relative}`.
              Create a wrapper flake with `scripts/external-input-flake.sh`
              or call `lib.mkOutputs { generated = <path>; }`.
              Supported default locations are `~/.local/share/nix-config-generated` on macOS
              and `/nixos-generated` inside the VMware guest.
            '';
    in {
      root = inputs.generated;
      inherit requireFile;
      readFile = relative: builtins.readFile (requireFile relative);
    };

  den = (nixpkgs.lib.evalModules {
    modules = [ ./default.nix ./hosts.nix (inputs.import-tree ./aspects) ];
    specialArgs = { inherit generated inputs overlays; };
  }).config;
in {
  inherit (den.flake) nixosConfigurations darwinConfigurations;

  # Sopsidy secret collector script (rbw/bitwarden backend)
  # Built for common host systems since collect-secrets runs locally,
  # not on the target VM.
  packages.aarch64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "aarch64-darwin"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
  packages.x86_64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "x86_64-darwin"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
  packages.aarch64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "aarch64-linux"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
  packages.x86_64-linux.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    hosts = {
      inherit (den.flake.nixosConfigurations) vm-aarch64;
    };
  };
}
