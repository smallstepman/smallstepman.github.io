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
              darwinGitCommitTouchIdGetPin = pkgs.stdenvNoCC.mkDerivation {
                name = "gpg-touchid-commit-get-pin";
                dontUnpack = true;
                buildCommand = ''
                  set -euo pipefail

                  app="$out/Applications/GPG commit signing.app"
                  executable="$app/Contents/MacOS/GPG commit signing"
                  mkdir -p "$app/Contents/MacOS" "$out/bin"

                  cat > "$app/Contents/Info.plist" <<'PLIST'
                  <?xml version="1.0" encoding="UTF-8"?>
                  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                  <plist version="1.0">
                    <dict>
                      <key>CFBundleDevelopmentRegion</key>
                      <string>English</string>
                      <key>CFBundleDisplayName</key>
                      <string>GPG commit signing</string>
                      <key>CFBundleExecutable</key>
                      <string>GPG commit signing</string>
                      <key>CFBundleIdentifier</key>
                      <string>org.nixos.gpg-touchid-commit-get-pin</string>
                      <key>CFBundleInfoDictionaryVersion</key>
                      <string>6.0</string>
                      <key>CFBundleName</key>
                      <string>GPG commit signing</string>
                      <key>CFBundlePackageType</key>
                      <string>APPL</string>
                      <key>LSUIElement</key>
                      <true/>
                    </dict>
                  </plist>
                  PLIST

                  cat > "$TMPDIR/gpg-touchid-commit-get-pin.swift" <<'SWIFT'
                  import Darwin
                  import Dispatch
                  import Foundation
                  import LocalAuthentication
                  import Security

                  let env = ProcessInfo.processInfo.environment
                  let keychainLabel = (env["GPG_TOUCHID_KEYCHAIN_LABEL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                  let fallbackReason = "Unlock the GPG commit signing key"
                  let promptReason = (env["GPG_TOUCHID_PROMPT_DESC"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                  let reason = promptReason.isEmpty ? fallbackReason : promptReason
                  let context = LAContext()
                  var error: NSError?

                  func fail(_ prefix: String, _ message: String, _ code: Int32) -> Never {
                      FileHandle.standardError.write(Data("\\(prefix): \\(message)\\n".utf8))
                      Darwin.exit(code)
                  }

                  guard !keychainLabel.isEmpty else {
                      fail("gpg-touchid-commit-get-pin", "missing GPG_TOUCHID_KEYCHAIN_LABEL", 2)
                  }

                  if #available(macOS 10.12.2, *) {
                      context.touchIDAuthenticationAllowableReuseDuration = 0
                  }

                  guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                      fail("gpg-touchid-commit-get-pin", error?.localizedDescription ?? "Touch ID is unavailable", 2)
                  }

                  let semaphore = DispatchSemaphore(value: 0)
                  var approved = false
                  var failureMessage: String?

                  context.evaluatePolicy(
                      .deviceOwnerAuthenticationWithBiometrics,
                      localizedReason: reason
                  ) { success, evalError in
                      approved = success
                      if let evalError, !success {
                          failureMessage = evalError.localizedDescription
                      }
                      semaphore.signal()
                  }

                  semaphore.wait()

                  if !approved {
                      if let failureMessage {
                          FileHandle.standardError.write(Data("gpg-touchid-commit-get-pin: \\(failureMessage)\\n".utf8))
                      }
                      Darwin.exit(1)
                  }

                  let query: [CFString: Any] = [
                      kSecClass: kSecClassGenericPassword,
                      kSecAttrService: "GnuPG",
                      kSecAttrLabel: keychainLabel,
                      kSecMatchLimit: kSecMatchLimitOne,
                      kSecReturnData: true,
                      kSecUseAuthenticationContext: context,
                  ]

                  var item: CFTypeRef?
                  let status = SecItemCopyMatching(query as CFDictionary, &item)
                  guard status == errSecSuccess else {
                      let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain lookup failed (\(status))"
                      fail("gpg-touchid-commit-get-pin", message, 2)
                  }

                  guard let data = item as? Data else {
                      fail("gpg-touchid-commit-get-pin", "Keychain lookup returned no data", 2)
                  }

                  FileHandle.standardOutput.write(data)
                  Darwin.exit(0)
                  SWIFT

                  if ! [ -x /usr/bin/swiftc ]; then
                    echo "gpg-touchid-commit-get-pin: swiftc not found; install Xcode Command Line Tools (docs/macbook.sh bootstraps them)." >&2
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
                text = ''
                  #!${pkgs.python3}/bin/python3
                  import hashlib
                  import json
                  import os
                  import re
                  import subprocess
                  import sys
                  from pathlib import Path
                  from urllib.parse import unquote

                  REAL = "/opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid"
                  GIT_COMMIT_TOUCHID_HELPER = os.environ.get("GPG_TOUCHID_COMMIT_HELPER") or "${darwinGitCommitTouchIdGetPin}/bin/gpg-touchid-commit-get-pin"
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

                  def decode_assuan_command_text(command):
                      if " " not in command:
                          return ""
                      payload = command.split(" ", 1)[1].rstrip("\n")
                      if payload.startswith('"') and payload.endswith('"'):
                          payload = payload[1:-1]
                      return unquote(payload)

                  def metadata_path_from_tty(tty_name):
                      if not tty_name:
                          return None

                      cache_home = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache"))
                      tty_key = re.sub(r"[^A-Za-z0-9._-]", "_", tty_name)
                      return cache_home / "gpg-touchid-signing-prompts" / f"{tty_key}.metadata"

                  def load_git_signing_prompt(tty_name):
                      metadata_path = metadata_path_from_tty(tty_name)
                      if metadata_path is None or not metadata_path.is_file():
                          return None

                      try:
                          pairs = {}
                          for raw_line in metadata_path.read_text().splitlines():
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
                          "display_desc": desc_text,
                          "payload_kind": payload_kind,
                      }

                  def git_keychain_label(desc_command):
                      if not desc_command or not desc_command.startswith("SETDESC "):
                          return None

                      desc_text = decode_assuan_command_text(desc_command)
                      identity_match = re.search(r'"([^"]+ <[^>]+>)"', desc_text)
                      key_id_match = re.search(r'ID (?:0x)?([0-9A-Fa-f]+),', desc_text)
                      if identity_match is None or key_id_match is None:
                          return None

                      return f"{identity_match.group(1)} ({key_id_match.group(1).upper()})"

                  def write_assuan_secret(secret):
                      sys.stdout.write(f"D {encode_assuan_data(secret)}\n")
                      sys.stdout.write("OK\n")
                      sys.stdout.flush()

                  def write_assuan_cancel():
                      sys.stdout.write("ERR 83886179 Operation cancelled <Pinentry>\n")
                      sys.stdout.flush()

                  def run_git_commit_touchid_helper(git_signing_prompt, original_desc):
                      if not os.path.isfile(GIT_COMMIT_TOUCHID_HELPER) or not os.access(GIT_COMMIT_TOUCHID_HELPER, os.X_OK):
                          return None

                      keychain_label = git_keychain_label(original_desc)
                      if not keychain_label:
                          return None

                      env = os.environ.copy()
                      env["GPG_TOUCHID_PAYLOAD_KIND"] = git_signing_prompt.get("payload_kind") or ""
                      env["GPG_TOUCHID_PROMPT_DESC"] = git_signing_prompt.get("display_desc") or ""
                      env["GPG_TOUCHID_KEYCHAIN_LABEL"] = keychain_label
                      result = subprocess.run(
                          [GIT_COMMIT_TOUCHID_HELPER],
                          capture_output=True,
                          check=False,
                          env=env,
                          text=True,
                      )

                      if result.returncode == 0:
                          return {"handled": True, "secret": result.stdout}
                      if result.returncode == 1:
                          return {"handled": True, "cancelled": True}
                      return None

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

                  git_signing_prompt = None
                  git_original_desc = None
                  session_kind = None

                  for raw in sys.stdin:
                      if raw.startswith("OPTION ttyname="):
                          tty_name = raw.split("=", 1)[1].rstrip("\n")
                          if session_kind is None:
                              git_signing_prompt = load_git_signing_prompt(tty_name)
                              if git_signing_prompt is not None:
                                  session_kind = "git"
                          send_and_forward(raw)
                          continue
                      if session_kind == "git" and raw.startswith("SETTITLE "):
                          send_and_forward(git_signing_prompt["title"] + "\n")
                          continue
                      if session_kind == "git" and raw.startswith("SETDESC "):
                          if git_original_desc is None:
                              git_original_desc = raw
                          send_and_forward(git_signing_prompt["desc"] + "\n")
                          continue
                      if raw == "GETPIN\n" and session_kind == "git" and git_signing_prompt is not None:
                          if git_signing_prompt.get("payload_kind") == "commit":
                              helper_result = run_git_commit_touchid_helper(git_signing_prompt, git_original_desc)
                              if helper_result is not None:
                                  if helper_result.get("cancelled"):
                                      write_assuan_cancel()
                                  else:
                                      write_assuan_secret(helper_result.get("secret") or "")
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

                gpg_touchid_metadata_path_for_tty() {
                  local tty_name="$1"
                  local metadata_dir
                  local tty_key

                  if [ -z "$tty_name" ]; then
                    return 1
                  fi

                  metadata_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/gpg-touchid-signing-prompts"
                  tty_key=$(printf '%s' "$tty_name" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
                  mkdir -p "$metadata_dir"
                  printf '%s/%s.metadata\n' "$metadata_dir" "$tty_key"
                }

                gpg_touchid_write_signing_metadata_file() {
                  local payload="$1"
                  local tty_name="$2"
                  local metadata_file

                  if [ -z "$tty_name" ]; then
                    return 1
                  fi

                  gpg_touchid_parse_signing_payload "$payload"
                  gpg_touchid_derive_repo_context

                  metadata_file=$(gpg_touchid_metadata_path_for_tty "$tty_name") || return 1

                  : >"$metadata_file"
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
                  local tty_name=""
                  local status

                  cleanup() {
                    gpg_touchid_cleanup_file "$metadata_file"
                    gpg_touchid_cleanup_file "$payload_file"
                  }

                  trap cleanup EXIT HUP INT TERM

                  payload_file=$(mktemp "''${TMPDIR:-/tmp}/gpg-touchid-signing-payload.XXXXXX")
                  cat >"$payload_file"
                  payload=$(cat "$payload_file")
                  tty_name="''${GPG_TTY:-}"
                  if [ -z "$tty_name" ]; then
                    tty_name=$(tty 2>/dev/null || true)
                  fi
                  if [ -n "$tty_name" ] && [ "$tty_name" != "not a tty" ]; then
                    metadata_file=$(gpg_touchid_write_signing_metadata_file "$payload" "$tty_name" || true)
                  fi

                  GPG_TOUCHID_METADATA_PATH="$metadata_file" "$gpg_bin" "$@" <"$payload_file"
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

              signing = {
                signByDefault = true;
              } // (lib.optionalAttrs isDarwin {
                signer = "${darwinGitSigningWrapper}/bin/gpg-touchid-signing-prompt";
              });
            };

            programs.gpg.enable = true;

            services.gpg-agent = {
              enable = true;
              defaultCacheTtl = lib.mkDefault 31536000;
              maxCacheTtl = lib.mkDefault 31536000;
            } // (lib.optionalAttrs isDarwin {
              extraConfig = "pinentry-program ${darwinRbwPinentryWrapper}/bin/rbw-pinentry-touchid";
            });

            home.file = lib.mkIf isDarwin {
              ".gitconfig".text = ''
                [include]
                	path = ~/.gitconfig.backup
                [include]
                	path = ~/.config/git/config
              '';
            };
            };
        })
    ];
  };
}
