{ inputs }: final: prev: {
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
}
