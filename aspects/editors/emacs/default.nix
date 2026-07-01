{ inputs, ... }: {
  den.aspects.editors.emacs = {
    homeManager = { lib, pkgs, ... }: let
      ghostelVersion = "0.38.0";
      emacsDaemonPath = [
        "/etc/profiles/per-user/m/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/opt/homebrew/bin"
        "/opt/homebrew/sbin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
      ];
      emacsDaemonPathString = lib.concatStringsSep ":" emacsDaemonPath;

      ghostelSrc = pkgs.fetchFromGitHub {
        owner = "dakra";
        repo = "ghostel";
        rev = "v${ghostelVersion}";
        hash = "sha256-om7zQadmKwfL59ydItJN9UfeAz2mw2OoFxOg6fcPY/s=";
      };

      ghostelModule = pkgs.stdenv.mkDerivation {
        pname = "ghostel-module";
        version = ghostelVersion;
        src = pkgs.fetchurl {
          url = "https://github.com/dakra/ghostel/releases/download/v${ghostelVersion}/ghostel-module-aarch64-macos.dylib";
          hash = "sha256-f193xQ+VruO3aM+u9fxB4+iaRAWIO2lsUlStXMz3Gkc=";
        };
        dontUnpack = true;
        installPhase = ''
          mkdir -p $out/lib
          cp $src $out/lib/libghostel-module.dylib
          chmod +x $out/lib/libghostel-module.dylib
          echo "${ghostelVersion}" > $out/ghostel-module.version
        '';
      };

      libExt = pkgs.stdenv.hostPlatform.extensions.sharedLibrary;

      ghostel = (pkgs.emacsPackagesFor pkgs.emacs-pgtk).melpaBuild {
        pname = "ghostel";
        version = ghostelVersion;
        src = ghostelSrc;
        files = ''
          ("lisp/*.el"
           "extensions/*.el"
           "etc")
        '';
        postInstall = let
          mod = ghostelModule;
        in ''
          dylib=$out/share/emacs/site-lisp/elpa/ghostel-${ghostelVersion}/ghostel-module${libExt}
          install ${mod}/lib/libghostel-module${libExt} $dylib
          install --mode=444 ${mod}/ghostel-module.version $out/share/emacs/site-lisp/elpa/ghostel-${ghostelVersion}/ghostel-module.version
        '';
      };

      emacs-lsp-booster = pkgs.rustPlatform.buildRustPackage rec {
        pname = "emacs-lsp-booster";
        version = "0.2.1";
        src = pkgs.fetchFromGitHub {
          owner = "blahgeek";
          repo = pname;
          rev = "v${version}";
          hash = "sha256-uP/xJfXQtk8oaG5Zk+dw+C2fVFdjpUZTDASFuj1+eYs=";
        };
        cargoHash = "sha256-BR0IELLzm+9coaiLXQn+Rw6VLyiFEAk/nkO08qPwAac=";
        doCheck = false;
        meta.mainProgram = "emacs-lsp-booster";
      };
    in {
      imports = [ inputs.nix-doom-emacs-unstraightened.homeModule ];

      home.packages = [ pkgs.emacs-all-the-icons-fonts ];

      programs.doom-emacs = {
        enable = true;
        doomDir = ./doom;
        emacs = pkgs.emacs-pgtk;
        extraBinPackages = [ emacs-lsp-booster ];
        extraPackages = epkgs: [ epkgs.vterm epkgs.treesit-grammars.with-all-grammars epkgs.ghostel ];
        emacsPackageOverrides = eself: esuper: {
          inherit ghostel;
        };
      };

      services.emacs = {
        enable = true;
        defaultEditor = false;
      };

      systemd.user.services.emacs.Service.Environment = lib.mkIf pkgs.stdenv.isLinux [
        "PATH=${emacsDaemonPathString}"
      ];

      launchd.agents.emacs.config.EnvironmentVariables = lib.mkIf pkgs.stdenv.isDarwin {
        PATH = emacsDaemonPathString;
      };
    };
  };
}
