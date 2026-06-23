{ ... }: final: prev: {
  wayprompt = prev.wayprompt.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./wayprompt-wayland-clipboard-paste.patch ];
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ final.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/wayprompt --prefix PATH : ${final.wl-clipboard}/bin
      wrapProgram $out/bin/pinentry-wayprompt --prefix PATH : ${final.wl-clipboard}/bin
    '';
  });
}
