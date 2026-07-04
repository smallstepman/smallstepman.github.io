{ lib, pkgs, ... }:
let
  omniwmVersion = "v0.5.2.1";

  # NUR's zip extraction leaves AppleDouble files that invalidate the signed app.
  omniwm = pkgs.nur.repos.doomhammer.omniwm.overrideAttrs (old: {
    version = omniwmVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/BarutSRB/OmniWM/releases/download/${omniwmVersion}/OmniWM-${omniwmVersion}.zip";
      hash = "sha256-V0Zj6P94iAou3rYpA+CCz1Vq8Ko3cETuzFtveGD4idc=";
    };

    postInstall = (old.postInstall or "") + ''
      find "$out" -name '._*' -delete
    '';
  });

  omniwmWithBin = pkgs.runCommand "${omniwm.name}-with-bin" {
    meta = omniwm.meta // {
      mainProgram = "omniwm";
    };
  } ''
    mkdir -p "$out/Applications" "$out/bin"

    ln -s "${omniwm}/Applications/OmniWM.app" "$out/Applications/OmniWM.app"
    ln -s "${omniwm}/Applications/OmniWM.app/Contents/MacOS/OmniWM" "$out/bin/omniwm"
    ln -s "${omniwm}/Applications/OmniWM.app/Contents/MacOS/omniwmctl" "$out/bin/omniwmctl"
  '';
in
{
  environment.systemPackages = [
    omniwmWithBin
  ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "setting up /Applications/OmniWM.app..." >&2

    omniwmSource="${omniwm}/Applications/OmniWM.app"
    omniwmTarget="/Applications/OmniWM.app"
    omniwmMarker="/Applications/.OmniWM.app.nix-managed"

    if [ -e "$omniwmTarget" ] && [ ! -f "$omniwmMarker" ]; then
      echo "warning: $omniwmTarget exists and is not marked as Nix-managed; leaving it untouched" >&2
    else
      mkdir -p "$omniwmTarget"
      ${pkgs.rsync}/bin/rsync \
        --checksum \
        --copy-unsafe-links \
        --archive \
        --delete \
        --chmod=-w \
        --no-group \
        --no-owner \
        "$omniwmSource/" \
        "$omniwmTarget"
      touch "$omniwmMarker"
    fi
  '';
}
