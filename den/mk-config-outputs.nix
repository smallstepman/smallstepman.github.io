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
        opencode = inputs.opencode.packages.${prev.stdenv.hostPlatform.system}.default;
        rbw = inputs.rbw.packages.${prev.stdenv.hostPlatform.system}.default;
        agent-of-empires = inputs.agent-of-empires-src.packages.${prev.stdenv.hostPlatform.system}.default;
        gastown = inputs.gastown.packages.${prev.stdenv.hostPlatform.system}.gt.overrideAttrs (old: {
          proxyVendor = true;
          vendorHash = "sha256-lct4BRPRh8nfNHE2p0SU0ZgItA8AbWU/AQPz+HbiPaI=";
        });

      llm-agents = prev.llm-agents // {
        beads-rust = prev.callPackage "${inputs.llm-agents.outPath}/packages/beads-rust/package.nix" {
          flake = inputs.llm-agents;
          rustPlatform = prev.rustPlatform // {
            buildRustPackage = args:
              prev.rustPlatform.buildRustPackage (
                args
                // {
                  # Vendor staging does not receive arbitrary attrs like
                  # `frankensqlite`, so interpolate its store path eagerly.
                  postUnpack = builtins.replaceStrings
                    [ "$frankensqlite" ]
                    [ "${args.frankensqlite}" ]
                    (args.postUnpack or "");
                }
              );
          };
        };
      };

      apm =
        let
          src = final.fetchFromGitHub {
            owner = "microsoft";
            repo = "apm";
            rev = "v0.7.3";
            hash = "sha256-B2gAGZpziIf5L7Unc+ojJlCKk8O7qWUnTYmtNFLsxKk=";
          };
          workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };
          overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
          # Fix upstream bug: get_auto_integrate / set_auto_integrate are called
          # in cli.py but missing from config.py (v0.7.3).
          pyprojectOverrides = _final: prev: {
            apm-cli = prev.apm-cli.overrideAttrs (old: {
              postInstall = (old.postInstall or "") + ''
                cfg=$(find $out -path "*/apm_cli/config.py" | head -1)
                cat >> "$cfg" << 'PYEOF'


def get_auto_integrate():
  return get_config().get("auto_integrate", True)


def set_auto_integrate(value: bool):
  update_config({"auto_integrate": value})
PYEOF
              '';
            });
          };
          pythonSet = (final.callPackage inputs.pyproject-nix.build.packages {
            python = final.python3;
          }).overrideScope (final.lib.composeManyExtensions [
            inputs.pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]);
        in
        pythonSet.mkVirtualEnv "apm" workspace.deps.default;

      uniclip = final.buildGoModule {
        pname = "uniclip";
        version = "0-unstable";
        src = inputs.uniclip-src;
        vendorHash = "sha256-ugrWrB0YVs/oWAR3TC3bEpt1VXQC1c3oLrvFJxlR8pw=";
        patches = [ ../patches/uniclip-bind-and-env-password.patch ];
        meta.description = "Universal clipboard - copy on one device, paste on another";
      };

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

      zellij =
        let
          rustToolchain = final.rust-bin.stable.latest.default;
          rustPlatform = final.makeRustPlatform {
            cargo = rustToolchain;
            rustc = rustToolchain;
          };
        in
        rustPlatform.buildRustPackage {
          pname = "zellij";
          version = "0.44.0";

          src = final.fetchFromGitHub {
            owner = "zellij-org";
            repo = "zellij";
            rev = "a6a6440";
            hash = "sha256-8dYKjGLhi02EpYunThXZnFkLMwyPTWunDtnm+svvJNk=";
          };

          patches = [
            ../patches/zellij-0001-add-move-pane-to-tab-cli.patch
            ../patches/zellij-0002-add-session-transfer-groundwork.patch
            ../patches/zellij-0003-add-move-pane-to-session-cli.patch
            ../patches/zellij-0004-add-move-tab-to-session-cli.patch
            ../patches/zellij-0005-harden-macos-session-transfer-sockets.patch
          ];

          cargoHash = "sha256-nGMOVq5etxiOfocjTKXAd8sJHFw34T49Ga48Isc8dCg=";

          postPatch = ''
            substituteInPlace Cargo.toml \
              --replace-fail ', "vendored_curl"' ""
          '';

          env.OPENSSL_NO_VENDOR = 1;

          nativeBuildInputs = [
            final.mandown
            final.installShellFiles
            final.pkg-config
            (final.lib.getDev final.curl)
          ];

          buildInputs = [
            final.curl
            final.openssl
          ];

          nativeCheckInputs = [ final.writableTmpDirAsHomeHook ];
          nativeInstallCheckInputs = [ final.versionCheckHook ];
          versionCheckProgramArg = "--version";
          doInstallCheck = true;

          installCheckPhase = final.lib.optionalString (final.stdenv.hostPlatform.libc == "glibc") ''
            runHook preInstallCheck

            ldd "$out/bin/zellij" | grep libcurl.so

            runHook postInstallCheck
          '';

          postInstall =
            ''
              mandown docs/MANPAGE.md > zellij.1
              installManPage zellij.1
            ''
            + final.lib.optionalString (final.stdenv.buildPlatform.canExecute final.stdenv.hostPlatform) ''
              installShellCompletion --cmd $pname \
                --bash <($out/bin/zellij setup --generate-completion bash) \
                --fish <($out/bin/zellij setup --generate-completion fish) \
                --zsh <($out/bin/zellij setup --generate-completion zsh)
            '';

          meta = {
            description = "Terminal workspace with batteries included";
            homepage = "https://zellij.dev/";
            license = [ final.lib.licenses.mit ];
            maintainers = with final.lib.maintainers; [
              therealansh
              _0x4A6F
              abbe
              matthiasbeyer
              ryan4yin
            ];
            mainProgram = "zellij";
          };
        };

      tmuxPlugins = prev.tmuxPlugins // {
        "tmux-menus" = final.tmuxPlugins.mkTmuxPlugin {
          pluginName = "tmux-menus";
          version = "0-unstable-2026-02-21";
          src = inputs.tmux-menus-src;
          rtpFilePath = "menus.tmux";
        };
      };

      dotagents = final.stdenv.mkDerivation (finalAttrs: {
        pname = "dotagents";
        version = "0.15.0";

        src = final.fetchFromGitHub {
          owner = "getsentry";
          repo = "dotagents";
          rev = finalAttrs.version;
          hash = "sha256-uqS2hh61urEtZ+ZLzyzdNChNA8kNNMemZUrV510uCfk=";
        };

        pnpmDeps = final.pnpm.fetchDeps {
          inherit (finalAttrs) pname version src;
          fetcherVersion = 1; # pnpm-lock.yaml lockfileVersion 9.0
          hash = "sha256-E2YJ2bw9OB3T1//2rtHx0dqgoYFKo4Cj59x13QdJj4s=";
        };

        nativeBuildInputs = [ final.pnpm.configHook final.nodejs_22 final.makeWrapper ];

        buildPhase = ''
          runHook preBuild
          pnpm build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          pnpm install --frozen-lockfile --prod
          mkdir -p $out/lib/node_modules/@sentry/dotagents
          cp -r dist package.json node_modules $out/lib/node_modules/@sentry/dotagents/
          mkdir -p $out/bin
          makeWrapper ${final.nodejs_22}/bin/node $out/bin/dotagents \
            --add-flags "$out/lib/node_modules/@sentry/dotagents/dist/cli/index.js"
          runHook postInstall
        '';

        meta = with final.lib; {
          description = "Package manager for AI agent skill dependencies";
          homepage = "https://github.com/getsentry/dotagents";
          license = licenses.mit;
          mainProgram = "dotagents";
          platforms = platforms.all;
        };
      });

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
