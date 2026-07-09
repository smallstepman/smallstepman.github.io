{
  package =
    { lib
    , stdenv
    , fetchFromGitHub
    , zig_0_16
    , git
    , xcodebuild
    , xcbuild
    , apple-sdk_15
    }:

    stdenv.mkDerivation (finalAttrs: {
      pname = "skhd-zig";
      version = "0.1.10";

      src = fetchFromGitHub {
        owner = "jackielii";
        repo = "skhd.zig";
        rev = "v${finalAttrs.version}";
        hash = "sha256-2ZExrFrdnf936oCkU0b5UGiI0KE5f8nroiyH85xQMUs=";
      };

      nativeBuildInputs = [
        zig_0_16
        git
        xcodebuild
        xcbuild
      ];

      buildInputs = [
        apple-sdk_15
      ];

      strictDeps = true;

      buildPhase = ''
        runHook preBuild
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        zig build -Doptimize=ReleaseFast --prefix "$out"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        rm -f "$out/bin/skhd-alloc"

        if [ ! -x "$out/bin/skhd" ]; then
          echo "error: $out/bin/skhd was not produced"
          find "$out" -maxdepth 4 -type f -print || true
          exit 1
        fi

        runHook postInstall
      '';

      meta = {
        description = "Simple Hotkey Daemon for macOS, Zig implementation";
        homepage = "https://github.com/jackielii/skhd.zig";
        license = lib.licenses.mit;
        platforms = lib.platforms.darwin;
        mainProgram = "skhd";
      };
    });
}
