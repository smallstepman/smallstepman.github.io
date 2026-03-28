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
          homeManager = { pkgs, lib, ... }:
            let
              darwinRbwPinentryWrapper = pkgs.writeTextFile {
                name = "rbw-pinentry-touchid";
                destination = "/bin/rbw-pinentry-touchid";
                executable = true;
                text = ''
                  #!${pkgs.python3}/bin/python3
                  import hashlib
                  import json
                  import subprocess
                  import sys
                  from pathlib import Path

                  REAL = "/opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid"
                  CFG = Path.home() / "Library/Application Support/rbw/config.json"

                  email = "rbw@local"
                  try:
                      cfg = json.loads(CFG.read_text())
                      email = cfg.get("email") or email
                  except Exception:
                      pass

                  key_id = hashlib.sha1(email.encode("utf-8")).hexdigest()[:8].upper()
                  keyinfo = f"rbw/{key_id}"
                  desc = f"SETDESC \\\"Bitwarden RBW <{email}>\\\" ID {key_id}, Unlock the local database for 'rbw'"

                  proc = subprocess.Popen(
                      [REAL],
                      stdin=subprocess.PIPE,
                      stdout=subprocess.PIPE,
                      stderr=subprocess.STDOUT,
                      text=True,
                      bufsize=1,
                  )

                  def read_response():
                      lines = []
                      while True:
                          line = proc.stdout.readline()
                          if line == "":
                              raise EOFError("pinentry-touchid closed stdout unexpectedly")
                          lines.append(line)
                          if line.startswith("OK") or line.startswith("ERR"):
                              return lines

                  def send_and_forward(command):
                      proc.stdin.write(command)
                      proc.stdin.flush()
                      for line in read_response():
                          sys.stdout.write(line)
                      sys.stdout.flush()

                  def send_and_require_ok(command):
                      proc.stdin.write(command)
                      proc.stdin.flush()
                      response = read_response()
                      if response[-1].startswith("ERR"):
                          for line in response:
                              sys.stdout.write(line)
                          sys.stdout.flush()
                          raise SystemExit(1)

                  for line in read_response():
                      sys.stdout.write(line)
                  sys.stdout.flush()

                  for raw in sys.stdin:
                      if raw.startswith("SETDESC "):
                          send_and_forward(desc + "\\n")
                          continue
                      if raw == "GETPIN\\n":
                          send_and_require_ok("OPTION allow-external-password-cache\\n")
                          send_and_require_ok(f"SETKEYINFO {keyinfo}\\n")
                          send_and_forward(raw)
                          continue
                      send_and_forward(raw)

                  try:
                      proc.stdin.close()
                  except Exception:
                      pass

                  raise SystemExit(proc.wait())
                '';
              };
            in {

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

            home.activation.ensureDarwinRbwPinentry = lib.mkIf isDarwin (
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                run ${pkgs.rbw}/bin/rbw config set pinentry ${darwinRbwPinentryWrapper}/bin/rbw-pinentry-touchid
              ''
            );

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
