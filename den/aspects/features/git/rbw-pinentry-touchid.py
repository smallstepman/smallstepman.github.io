#!__PYTHON_BIN__/bin/python3
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

REAL = "/opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid"
GIT_COMMIT_TOUCHID_HELPER = os.environ.get("GPG_TOUCHID_COMMIT_HELPER") or "__GIT_COMMIT_TOUCHID_HELPER__"
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
                
