{ pkgs, lib, ... }: let
  vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";

  vmGitSigningWrapper = pkgs.writeShellScriptBin "vm-gpg-touchid-signing" ''
    set -euo pipefail

    vm_gpg_touchid_parse_identity() {
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

    vm_gpg_touchid_parse_signing_payload() {
      local payload="$1"
      local line
      local in_headers=1
      local author_name=""
      local author_email=""
      local parsed_identity

      VM_GPG_TOUCHID_PAYLOAD_KIND="unknown"
      VM_GPG_TOUCHID_PAYLOAD_SUBJECT=""
      VM_GPG_TOUCHID_TAG_NAME=""
      VM_GPG_TOUCHID_SIGNER_NAME=""
      VM_GPG_TOUCHID_SIGNER_EMAIL=""

      while IFS= read -r line || [ -n "$line" ]; do
        if [ "$in_headers" -eq 1 ]; then
          case "$line" in
            tree\ *)
              VM_GPG_TOUCHID_PAYLOAD_KIND="commit"
              ;;
            author\ *)
              parsed_identity=$(vm_gpg_touchid_parse_identity "''${line#author }")
              author_name=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
              author_email=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
              ;;
            committer\ *)
              parsed_identity=$(vm_gpg_touchid_parse_identity "''${line#committer }")
              VM_GPG_TOUCHID_SIGNER_NAME=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
              VM_GPG_TOUCHID_SIGNER_EMAIL=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
              ;;
            object\ *)
              if [ "$VM_GPG_TOUCHID_PAYLOAD_KIND" = "unknown" ]; then
                VM_GPG_TOUCHID_PAYLOAD_KIND="tag"
              fi
              ;;
            tag\ *)
              VM_GPG_TOUCHID_TAG_NAME="''${line#tag }"
              ;;
            tagger\ *)
              parsed_identity=$(vm_gpg_touchid_parse_identity "''${line#tagger }")
              VM_GPG_TOUCHID_SIGNER_NAME=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
              VM_GPG_TOUCHID_SIGNER_EMAIL=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
              ;;
            "")
              in_headers=0
              ;;
          esac
          continue
        fi
        if [ -n "$line" ]; then
          VM_GPG_TOUCHID_PAYLOAD_SUBJECT="$line"
          break
        fi
      done <<< "$payload"

      if [ -z "$VM_GPG_TOUCHID_SIGNER_NAME" ] && [ -z "$VM_GPG_TOUCHID_SIGNER_EMAIL" ]; then
        VM_GPG_TOUCHID_SIGNER_NAME="$author_name"
        VM_GPG_TOUCHID_SIGNER_EMAIL="$author_email"
      fi
    }

    vm_gpg_touchid_derive_repo_context() {
      local common_dir
      local repo_root
      VM_GPG_TOUCHID_REPO_NAME=""
      VM_GPG_TOUCHID_REPO_BRANCH=""
      common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
      case "$common_dir" in
        */.git) VM_GPG_TOUCHID_REPO_NAME=$(basename "$(dirname "$common_dir")") ;;
        ?*) VM_GPG_TOUCHID_REPO_NAME=$(basename "$common_dir") ;;
      esac
      if [ -z "$VM_GPG_TOUCHID_REPO_NAME" ]; then
        repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
        [ -n "$repo_root" ] && VM_GPG_TOUCHID_REPO_NAME=$(basename "$repo_root")
      fi
      VM_GPG_TOUCHID_REPO_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "detached")
    }

    vm_gpg_touchid_cleanup_file() {
      local path="''${1:-}"
      [ -n "$path" ] && [ -e "$path" ] && rm -f -- "$path"
    }

    vm_gpg_touchid_metadata_path_for_tty() {
      local tty_name="$1"
      [ -z "$tty_name" ] && return 1
      local metadata_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/gpg-touchid-signing-prompts"
      local tty_key=$(printf '%s' "$tty_name" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
      mkdir -p "$metadata_dir"
      printf '%s/%s.metadata\n' "$metadata_dir" "$tty_key"
    }

    vm_gpg_touchid_write_signing_metadata_file() {
      local payload="$1"
      local tty_name="$2"
      [ -z "$tty_name" ] && return 1
      vm_gpg_touchid_parse_signing_payload "$payload"
      vm_gpg_touchid_derive_repo_context
      local metadata_file=$(vm_gpg_touchid_metadata_path_for_tty "$tty_name") || return 1
      : >"$metadata_file"
      chmod 600 "$metadata_file"
      {
        printf 'payload_kind=%s\n' "$VM_GPG_TOUCHID_PAYLOAD_KIND"
        printf 'payload_subject=%s\n' "$VM_GPG_TOUCHID_PAYLOAD_SUBJECT"
        printf 'tag_name=%s\n' "$VM_GPG_TOUCHID_TAG_NAME"
        printf 'signer_name=%s\n' "$VM_GPG_TOUCHID_SIGNER_NAME"
        printf 'signer_email=%s\n' "$VM_GPG_TOUCHID_SIGNER_EMAIL"
        printf 'repo_name=%s\n' "$VM_GPG_TOUCHID_REPO_NAME"
        printf 'repo_branch=%s\n' "$VM_GPG_TOUCHID_REPO_BRANCH"
      } >"$metadata_file"
      printf '%s\n' "$metadata_file"
    }

    vm_gpg_touchid_detect_tty_name() {
      local tty_name="''${GPG_TTY:-}"
      local ps_tty="" controlling_tty="" stdin_tty=""
      [ -z "$tty_name" ] && [ -r /dev/tty ] && controlling_tty=$(tty </dev/tty 2>/dev/null || true)
      [ -z "$tty_name" ] && [ -n "$controlling_tty" ] && [ "$controlling_tty" != "not a tty" ] && [ "$controlling_tty" != "/dev/tty" ] && tty_name="$controlling_tty"
      if [ -z "$tty_name" ]; then
        ps_tty=$(ps -o tty= -p "$$" 2>/dev/null | tr -d '[:space:]' || true)
        case "$ps_tty" in ""|"?"|"??"|notty) ps_tty="";; /dev/*) ;; *) ps_tty="/dev/$ps_tty";; esac
      fi
      [ -z "$tty_name" ] && [ -n "$ps_tty" ] && [ "$ps_tty" != "/dev/tty" ] && tty_name="$ps_tty"
      [ -z "$tty_name" ] && stdin_tty=$(tty 2>/dev/null || true)
      [ -z "$tty_name" ] && [ -n "$stdin_tty" ] && [ "$stdin_tty" != "not a tty" ] && tty_name="$stdin_tty"
      [ -z "$tty_name" ] && [ -n "$controlling_tty" ] && [ "$controlling_tty" != "not a tty" ] && tty_name="$controlling_tty"
      [ -z "$tty_name" ] && [ -n "$stdin_tty" ] && [ "$stdin_tty" != "not a tty" ] && tty_name="$stdin_tty"
      [ -n "$tty_name" ] && [ "$tty_name" != "not a tty" ] && printf '%s\n' "$tty_name" && return 0
      return 1
    }

    vm_gpg_touchid_exec_gpg_with_metadata() {
      local gpg_bin="''${GPG_TOUCHID_GPG_BIN:-${pkgs.gnupg}/bin/gpg}"
      local payload_file="" metadata_file="" payload="" tty_name=""
      cleanup() { vm_gpg_touchid_cleanup_file "$metadata_file"; vm_gpg_touchid_cleanup_file "$payload_file"; }
      payload_file=$(mktemp "''${TMPDIR:-/tmp}/vm-gpg-touchid-signing-payload.XXXXXX")
      cat >"$payload_file"
      payload=$(cat "$payload_file")
      tty_name=$(vm_gpg_touchid_detect_tty_name || true)
      [ -n "$tty_name" ] && [ "$tty_name" != "not a tty" ] && metadata_file=$(vm_gpg_touchid_write_signing_metadata_file "$payload" "$tty_name" || true)
      trap cleanup EXIT HUP INT TERM
      GPG_TOUCHID_METADATA_PATH="$metadata_file" exec "$gpg_bin" "$@" <"$payload_file"
      local status=$?; cleanup; return "$status"
    }

    vm_gpg_touchid_exec_gpg_with_metadata "$@"
  '';

  repairSharedGitFileMode = pkgs.writeShellScriptBin "repair-shared-git-filemode" ''
    set -euo pipefail
    git_bin=${pkgs.git}/bin/git
    repair_repo() {
      local root="$1"
      case "$root" in /nixos-config|/Users/m/Projects|/Users/m/Projects/*) ;; *) return 0 ;; esac
      "$git_bin" -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
      "$git_bin" -C "$root" config core.fileMode false
      "$git_bin" -C "$root" submodule foreach --quiet 'git config core.fileMode false' 2>/dev/null || true
    }
    if [ "$#" -eq 0 ]; then repair_repo /nixos-config; exit 0; fi
    for repo in "$@"; do repair_repo "$repo"; done
  '';

  repairingGit = pkgs.writeShellScriptBin "git" ''
    set -euo pipefail
    git_bin=${pkgs.git}/bin/git
    realpath_bin=${pkgs.coreutils}/bin/realpath
    repair_bin=${repairSharedGitFileMode}/bin/repair-shared-git-filemode

    resolve_workdir() {
      local dir="$PWD"; local work_tree=""; local git_dir_only=0
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -C) [ "$#" -ge 2 ] || break; case "$2" in /*) dir=$("$realpath_bin" -m "$2") ;; *) dir=$("$realpath_bin" -m "$dir/$2") ;; esac; shift 2 ;;
          --work-tree) [ "$#" -ge 2 ] || break; case "$2" in /*) work_tree=$("$realpath_bin" -m "$2") ;; *) work_tree=$("$realpath_bin" -m "$dir/$2") ;; esac; shift 2 ;;
          --work-tree=*) case "''${1#*=}" in /*) work_tree=$("$realpath_bin" -m "''${1#*=}") ;; *) work_tree=$("$realpath_bin" -m "$dir/''${1#*=}") ;; esac; shift ;;
          --git-dir) [ "$#" -ge 2 ] || break; git_dir_only=1; shift 2 ;;
          --git-dir=*) git_dir_only=1; shift ;;
          --) break ;;
          -c|--exec-path|--namespace|--super-prefix|--config-env) [ "$#" -ge 2 ] || break; shift 2 ;;
          --exec-path=*|--namespace=*|--super-prefix=*|--config-env=*) shift ;;
          -*) shift ;;
          *) break ;;
        esac
      done
      [ -n "$work_tree" ] && dir="$work_tree"
      [ "$git_dir_only" -eq 1 ] && return 1
      printf '%s\n' "$dir"
    }

    if workdir=$(resolve_workdir "$@"); then
      if root=$("$git_bin" -C "$workdir" rev-parse --show-toplevel 2>/dev/null); then
        "$repair_bin" "$root"
      fi
    fi
    exec "$git_bin" "$@"
  '';
in {
  den.aspects.git.vm-signing = {
    homeManager = { pkgs, lib, ... }: {
      home.packages = [
        pkgs.docker-client
      ];

      home.sessionVariables = {
        DOCKER_CONTEXT = "host-mac";
      };

      programs.git.signing.key = vmGitSigningKey;
      programs.git.signing.signer = "${vmGitSigningWrapper}/bin/vm-gpg-touchid-signing";
      programs.git.settings.gpg.program = "${vmGitSigningWrapper}/bin/vm-gpg-touchid-signing";
      programs.git.package = repairingGit;


      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks."mac-host-docker" = {
          hostname = "192.168.130.1";
          user = "m";
          identityFile = "~/.ssh/id_ed25519";
          controlMaster = "auto";
          controlPersist = "10m";
          controlPath = "~/.ssh/control-%h-%p-%r";
          serverAliveInterval = 30;
        };
      };

      home.activation.ensureHostDockerContext =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ! ${pkgs.docker-client}/bin/docker context inspect host-mac >/dev/null 2>&1; then
            run ${pkgs.docker-client}/bin/docker context create host-mac \
              --docker "host=ssh://m@mac-host-docker"
          fi
        '';

      home.activation.ensureSharedGitFileMode =
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${repairSharedGitFileMode}/bin/repair-shared-git-filemode /nixos-config
        '';

      systemd.user.services."repair-shared-git-filemode" = {
        Unit = {
          Description = "Repair Git fileMode for HGFS-backed shared repos";
          After = [ "default.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${repairSharedGitFileMode}/bin/repair-shared-git-filemode";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
