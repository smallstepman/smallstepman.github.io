{ lib, ... }: {
  den.aspects.git = {
    homeManager = { pkgs, lib, ... }:
    let
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      isLinux = !isDarwin;
      darwinStuff = if isDarwin then import ./_darwin.nix { inherit pkgs; } else null;
    in {
      home.packages = [
        pkgs.tig
      ] ++ (lib.optionals isDarwin [
        darwinStuff.darwinGitCommitTouchIdGetPin
      ]) ++ (lib.optionals isLinux [
        (pkgs.writeShellScriptBin "git-credential-github" ''
          case "$1" in
            get)
              while IFS='=' read -r key value; do
                [ -z "$key" ] && break
                case "$key" in host) host="$value" ;; esac
              done
              case "$host" in
                github.com|gist.github.com)
                  token=$(${pkgs.rbw}/bin/rbw get github-token 2>/dev/null)
                  [ -n "$token" ] && printf 'protocol=https\nhost=%s\nusername=smallstepman\npassword=%s\n' "$host" "$token"
                  ;;
              esac
              ;;
          esac
        '')
      ]);

      programs.gh = {
        enable = true;
        gitCredentialHelper.enable = isDarwin;
      };

      programs.rbw = lib.mkIf isLinux {
        enable = true;
        settings = {
          base_url = "https://api.bitwarden.eu";
          email = "overwritten-by-systemd";
          lock_timeout = 86400;
        };
      };

      programs.git = {
        enable = true;
        settings = {
          user.name   = "Marcin Nowak Liebiediew";
          user.email  = "m.liebiediew@gmail.com";
          branch.autosetuprebase = "always";
          color.ui   = true;
          core.askPass        = "";
          core.fileMode       = !isDarwin;
          core.untrackedCache = true;
          github.user         = "smallstepman";
          push.default        = "tracking";
          init.defaultBranch  = "main";
          aliases = {
            cleanup   = "!git branch --merged | grep -v '\*\|master\|develop' | xargs -n1 -r git branch -d";
            prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
            root      = "rev-parse --show-toplevel";
            ce        = "git commit --amend --no-edit";
          };
        } // (lib.optionalAttrs isDarwin {
          gpg.program = "${darwinStuff.darwinGitSigningWrapper}/bin/gpg-touchid-signing-prompt";
        });

        signing = {
          signByDefault = true;
        } // (lib.optionalAttrs isDarwin {
          signer = "${darwinStuff.darwinGitSigningWrapper}/bin/gpg-touchid-signing-prompt";
        });
      };

      programs.gpg.enable = true;

      services.gpg-agent = {
        enable = true;
        defaultCacheTtl = lib.mkDefault 31536000;
        maxCacheTtl = lib.mkDefault 31536000;
      } // (lib.optionalAttrs isDarwin {
        extraConfig = "pinentry-program ${darwinStuff.darwinRbwPinentryWrapper}/bin/rbw-pinentry-touchid";
      });

      home.activation.ensureDarwinRbwPinentry = lib.mkIf isDarwin (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${pkgs.rbw}/bin/rbw config set pinentry ${darwinStuff.darwinRbwPinentryWrapper}/bin/rbw-pinentry-touchid
        ''
      );

      home.file = lib.mkIf isDarwin {
        ".gitconfig".text = ''
          [include]
          	path = ~/.gitconfig.backup
          [include]
          	path = ~/.config/git/config
        '';
      };
    };
  };
}
