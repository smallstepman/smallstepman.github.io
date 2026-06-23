{ pkgs }:
let
  darwinGitCommitTouchIdGetPin = pkgs.stdenvNoCC.mkDerivation {
    name = "gpg-touchid-commit-get-pin";
    dontUnpack = true;
    src = ./gpg-touchid-commit-get-pin.swift;
    plist = ./gpg-touchid-commit-get-pin.plist;
    buildCommand = ''
      set -euo pipefail
      app="$out/Applications/GPG commit signing.app"
      executable="$app/Contents/MacOS/GPG commit signing"
      mkdir -p "$app/Contents/MacOS" "$out/bin"
      cp "$plist" "$app/Contents/Info.plist"
      cp "$src" "$TMPDIR/gpg-touchid-commit-get-pin.swift"
      if ! [ -x /usr/bin/swiftc ]; then
        echo "gpg-touchid-commit-get-pin: swiftc not found" >&2
        exit 1
      fi
      /usr/bin/swiftc "$TMPDIR/gpg-touchid-commit-get-pin.swift" -o "$executable"
      ln -s "$executable" "$out/bin/gpg-touchid-commit-get-pin"
    '';
  };

  darwinRbwPinentryWrapper = pkgs.writeTextFile {
    name = "rbw-pinentry-touchid";
    destination = "/bin/rbw-pinentry-touchid";
    executable = true;
    text = builtins.replaceStrings
      [ "__GIT_COMMIT_TOUCHID_HELPER__" "__PYTHON_BIN__" ]
      [ "${darwinGitCommitTouchIdGetPin}/bin/gpg-touchid-commit-get-pin" "${pkgs.python3}" ]
      (builtins.readFile ./rbw-pinentry-touchid.py);
  };

  darwinGitSigningWrapper = pkgs.writeShellScriptBin "gpg-touchid-signing-prompt" (builtins.readFile ./gpg-touchid-signing-prompt.sh);
in
{
  inherit darwinGitCommitTouchIdGetPin darwinRbwPinentryWrapper darwinGitSigningWrapper;
}
