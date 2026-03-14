{ den, lib, ... }: {

  den.aspects.git = {
    includes = [
      ({ host, ... }:
        let
          isDarwin      = host.class == "darwin";
          isLinux       = host.class == "nixos";
          isWSL         = host.wsl.enable or false;
          isNonWSLLinux = isLinux && !isWSL;
        in {
          homeManager = { pkgs, lib, ... }: {

            home.packages = [
              pkgs.tig
            ] ++ (lib.optionals isNonWSLLinux [
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

            programs.git = {
              enable = true;
              settings = {
                user.name   = "Marcin Nowak Liebiediew";
                user.email  = "m.liebiediew@gmail.com";
                branch.autosetuprebase = "always";
                color.ui   = true;
                core.askPass        = "";
                core.fileMode       = !isLinux;
                core.untrackedCache = true;
                github.user         = "smallstepman";
                push.default        = "tracking";
                init.defaultBranch  = "main";
                aliases = {
                  cleanup   = "!gitbranch--merged|grep-v'\\*\\|master\\|develop'|xargs-n1-rgitbranch-d";
                  prettylog = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(r) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
                  root      = "rev-parse --show-toplevel";
                  ce        = "git commit --amend --no-edit";
                };
              } // (lib.optionalAttrs isLinux {
                "credential \"https://github.com\"".helper  = "github";
                "credential \"https://gist.github.com\"".helper = "github";
              });

              signing.signByDefault = true;
            };

            programs.gpg.enable = true;

            services.gpg-agent = {
              enable = true;
              defaultCacheTtl = lib.mkDefault 31536000;
              maxCacheTtl = lib.mkDefault 31536000;
            };

          };
        })
    ];
  };

}
