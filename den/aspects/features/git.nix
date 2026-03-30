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
                  import os
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
                  desc = f"SETDESC \"Bitwarden RBW <{email}>\" ID {key_id}, Unlock the local database for 'rbw'"

                  def quote_assuan(value):
                      return value.replace("\\", "\\\\").replace('"', '\\"')

                  def encode_assuan_data(value):
                      return (
                          value.replace("%", "%25")
                          .replace("\r", "%0D")
                          .replace("\n", "%0A")
                      )

                  def load_git_signing_prompt():
                      metadata_path = os.environ.get("PINENTRY_USER_DATA") or ""
                      if not metadata_path:
                          return None

                      try:
                          pairs = {}
                          for raw_line in Path(metadata_path).read_text().splitlines():
                              if "=" not in raw_line:
                                  continue
                              key, value = raw_line.split("=", 1)
                              pairs[key] = value
                      except Exception:
                          return None

                      payload_kind = pairs.get("payload_kind") or ""
                      payload_subject = pairs.get("payload_subject") or ""
                      signer_name = pairs.get("signer_name") or ""
                      signer_email = pairs.get("signer_email") or ""
                      repo_name = pairs.get("repo_name") or ""
                      repo_branch = pairs.get("repo_branch") or "detached"

                      if payload_kind not in {"commit", "tag"}:
                          return None

                      if not repo_name and not payload_subject and not signer_name and not signer_email:
                          return None

                      if payload_kind == "tag":
                          title_text = "GPG tag signing"
                          subject_label = "Tag"
                      else:
                          title_text = "GPG commit signing"
                          subject_label = "Commit"

                      signer = f"{signer_name} <{signer_email}>".strip()
                      desc_text = "\n".join([
                          f"Repo: {repo_name or 'repository'}",
                          f"Branch: {repo_branch}",
                          f"{subject_label}: {payload_subject}",
                          f"Signer: {signer}",
                      ])
                      title = f'SETTITLE "{quote_assuan(title_text)}"'
                      prompt_desc = f'SETDESC "{quote_assuan(encode_assuan_data(desc_text))}"'
                      return {
                          "title": title,
                          "desc": prompt_desc,
                      }

                  def is_rbw_desc(command):
                      return "local database for 'rbw'" in command or "Bitwarden" in command

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

                  git_signing_prompt = load_git_signing_prompt()
                  session_kind = "git" if git_signing_prompt is not None else None

                  for raw in sys.stdin:
                      if session_kind == "git" and raw.startswith("SETTITLE "):
                          send_and_forward(git_signing_prompt["title"] + "\n")
                          continue
                      if session_kind == "git" and raw.startswith("SETDESC "):
                          send_and_forward(git_signing_prompt["desc"] + "\n")
                          continue
                      if raw.startswith("SETDESC ") and is_rbw_desc(raw):
                          session_kind = "rbw"
                          send_and_forward(desc + "\n")
                          continue
                      if raw == "GETPIN\n" and session_kind == "rbw":
                          send_and_require_ok("OPTION allow-external-password-cache\n")
                          send_and_require_ok(f"SETKEYINFO {keyinfo}\n")
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
              darwinGitSigningWrapper = pkgs.writeShellScriptBin "gpg-touchid-signing-prompt" ''
                # gpg-touchid-signing-prompt helpers start
                gpg_touchid_parse_identity() {
                  local identity="$1"
                  local parsed_name=""
                  local parsed_email=""

                  if [ "$identity" != "''${identity#* <}" ]; then
                    parsed_name="''${identity%% <*}"
                    parsed_email="''${identity#*<}"
                    parsed_email="''${parsed_email%%>*}"
                  fi

                  printf '%s\n%s\n' "$parsed_name" "$parsed_email"
                }

                gpg_touchid_parse_signing_payload() {
                  local payload="$1"
                  local line
                  local in_headers=1
                  local author_name=""
                  local author_email=""
                  local parsed_identity

                  GPG_TOUCHID_SIGNING_PAYLOAD_KIND="unknown"
                  GPG_TOUCHID_SIGNING_PAYLOAD_SUBJECT=""
                  GPG_TOUCHID_SIGNING_TAG_NAME=""
                  GPG_TOUCHID_SIGNING_SIGNER_NAME=""
                  GPG_TOUCHID_SIGNING_SIGNER_EMAIL=""

                  while IFS= read -r line || [ -n "$line" ]; do
                    if [ "$in_headers" -eq 1 ]; then
                      case "$line" in
                        tree\ *)
                          GPG_TOUCHID_SIGNING_PAYLOAD_KIND="commit"
                          ;;
                        author\ *)
                          parsed_identity=$(gpg_touchid_parse_identity "''${line#author }")
                          author_name=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
                          author_email=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
                          ;;
                        committer\ *)
                          parsed_identity=$(gpg_touchid_parse_identity "''${line#committer }")
                          GPG_TOUCHID_SIGNING_SIGNER_NAME=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
                          GPG_TOUCHID_SIGNING_SIGNER_EMAIL=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
                          ;;
                        object\ *)
                          if [ "$GPG_TOUCHID_SIGNING_PAYLOAD_KIND" = "unknown" ]; then
                            GPG_TOUCHID_SIGNING_PAYLOAD_KIND="tag"
                          fi
                          ;;
                        tag\ *)
                          GPG_TOUCHID_SIGNING_TAG_NAME="''${line#tag }"
                          ;;
                        tagger\ *)
                          parsed_identity=$(gpg_touchid_parse_identity "''${line#tagger }")
                          GPG_TOUCHID_SIGNING_SIGNER_NAME=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
                          GPG_TOUCHID_SIGNING_SIGNER_EMAIL=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
                          ;;
                         "")
                           in_headers=0
                           ;;
                       esac
                      continue
                    fi

                    if [ -n "$line" ]; then
                      GPG_TOUCHID_SIGNING_PAYLOAD_SUBJECT="$line"
                      break
                    fi
                  done <<< "$payload"

                  if [ -z "$GPG_TOUCHID_SIGNING_SIGNER_NAME" ] && [ -z "$GPG_TOUCHID_SIGNING_SIGNER_EMAIL" ]; then
                    GPG_TOUCHID_SIGNING_SIGNER_NAME="$author_name"
                    GPG_TOUCHID_SIGNING_SIGNER_EMAIL="$author_email"
                  fi
                }

                gpg_touchid_derive_repo_context() {
                  local common_dir
                  local repo_root

                  GPG_TOUCHID_SIGNING_REPO_NAME=""
                  GPG_TOUCHID_SIGNING_REPO_BRANCH=""

                  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
                  case "$common_dir" in
                    */.git)
                      GPG_TOUCHID_SIGNING_REPO_NAME=$(basename "$(dirname "$common_dir")")
                      ;;
                    ?*)
                      GPG_TOUCHID_SIGNING_REPO_NAME=$(basename "$common_dir")
                      ;;
                  esac

                  if [ -z "$GPG_TOUCHID_SIGNING_REPO_NAME" ]; then
                    repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
                    if [ -n "$repo_root" ]; then
                      GPG_TOUCHID_SIGNING_REPO_NAME=$(basename "$repo_root")
                    fi
                  fi

                  GPG_TOUCHID_SIGNING_REPO_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
                  if [ -z "$GPG_TOUCHID_SIGNING_REPO_BRANCH" ]; then
                    GPG_TOUCHID_SIGNING_REPO_BRANCH="detached"
                  fi
                }

                gpg_touchid_cleanup_file() {
                  local path="''${1:-}"

                  if [ -n "$path" ] && [ -e "$path" ]; then
                    rm -f -- "$path"
                  fi
                }

                gpg_touchid_write_signing_metadata_file() {
                  local payload="$1"
                  local metadata_file

                  gpg_touchid_parse_signing_payload "$payload"
                  gpg_touchid_derive_repo_context

                  metadata_file=$(mktemp "''${TMPDIR:-/tmp}/gpg-touchid-signing-metadata.XXXXXX")
                  chmod 600 "$metadata_file"

                  {
                    printf 'payload_kind=%s\n' "$GPG_TOUCHID_SIGNING_PAYLOAD_KIND"
                    printf 'payload_subject=%s\n' "$GPG_TOUCHID_SIGNING_PAYLOAD_SUBJECT"
                    printf 'tag_name=%s\n' "$GPG_TOUCHID_SIGNING_TAG_NAME"
                    printf 'signer_name=%s\n' "$GPG_TOUCHID_SIGNING_SIGNER_NAME"
                    printf 'signer_email=%s\n' "$GPG_TOUCHID_SIGNING_SIGNER_EMAIL"
                    printf 'repo_name=%s\n' "$GPG_TOUCHID_SIGNING_REPO_NAME"
                    printf 'repo_branch=%s\n' "$GPG_TOUCHID_SIGNING_REPO_BRANCH"
                  } >"$metadata_file"

                  printf '%s\n' "$metadata_file"
                }

                gpg_touchid_exec_gpg_with_metadata() {
                  local gpg_bin="''${GPG_TOUCHID_GPG_BIN:-/opt/homebrew/bin/gpg}"
                  local payload_file=""
                  local metadata_file=""
                  local payload=""
                  local status

                  cleanup() {
                    gpg_touchid_cleanup_file "$metadata_file"
                    gpg_touchid_cleanup_file "$payload_file"
                  }

                  trap cleanup EXIT HUP INT TERM

                  payload_file=$(mktemp "''${TMPDIR:-/tmp}/gpg-touchid-signing-payload.XXXXXX")
                  cat >"$payload_file"
                  payload=$(cat "$payload_file")
                  metadata_file=$(gpg_touchid_write_signing_metadata_file "$payload")

                  PINENTRY_USER_DATA="$metadata_file" "$gpg_bin" "$@" <"$payload_file"
                  status=$?

                  cleanup
                  trap - EXIT HUP INT TERM
                  return "$status"
                }
                # gpg-touchid-signing-prompt helpers end

                gpg_touchid_exec_gpg_with_metadata "$@"
              '';
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
                }) // (lib.optionalAttrs isDarwin {
                  gpg.program = "${darwinGitSigningWrapper}/bin/gpg-touchid-signing-prompt";
                });

              signing.signByDefault = true;
            };

            programs.gpg.enable = true;

            services.gpg-agent = {
              enable = true;
              defaultCacheTtl = lib.mkDefault 31536000;
              maxCacheTtl = lib.mkDefault 31536000;
            } // (lib.optionalAttrs isDarwin {
              extraConfig = "pinentry-program ${darwinRbwPinentryWrapper}/bin/rbw-pinentry-touchid";
            });
            };
        })
    ];
  };
}
