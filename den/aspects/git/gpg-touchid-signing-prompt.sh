# gpg-touchid-signing-prompt helpers start
gpg_touchid_parse_identity() {
  local identity="$1"
  local parsed_name=""
  local parsed_email=""

  if [ "$identity" != "${identity#* <}" ]; then
    parsed_name="${identity%% <*}"
    parsed_email="${identity#*<}"
    parsed_email="${parsed_email%%>*}"
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
          parsed_identity=$(gpg_touchid_parse_identity "${line#author }")
          author_name=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
          author_email=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
          ;;
        committer\ *)
          parsed_identity=$(gpg_touchid_parse_identity "${line#committer }")
          GPG_TOUCHID_SIGNING_SIGNER_NAME=$(printf '%s\n' "$parsed_identity" | sed -n '1p')
          GPG_TOUCHID_SIGNING_SIGNER_EMAIL=$(printf '%s\n' "$parsed_identity" | sed -n '2p')
          ;;
        object\ *)
          if [ "$GPG_TOUCHID_SIGNING_PAYLOAD_KIND" = "unknown" ]; then
            GPG_TOUCHID_SIGNING_PAYLOAD_KIND="tag"
          fi
          ;;
        tag\ *)
          GPG_TOUCHID_SIGNING_TAG_NAME="${line#tag }"
          ;;
        tagger\ *)
          parsed_identity=$(gpg_touchid_parse_identity "${line#tagger }")
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
  local path="${1:-}"

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

  metadata_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gpg-touchid-signing-prompts"
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
  local gpg_bin="${GPG_TOUCHID_GPG_BIN:-/opt/homebrew/bin/gpg}"
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

  payload_file=$(mktemp "${TMPDIR:-/tmp}/gpg-touchid-signing-payload.XXXXXX")
  cat >"$payload_file"
  payload=$(cat "$payload_file")
  tty_name="${GPG_TTY:-}"
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
              
