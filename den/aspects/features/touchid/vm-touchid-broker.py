#!__PYTHON_BIN__
import argparse
import hashlib
import json
import os
import socket
import subprocess
import threading
import urllib.parse
from pathlib import Path


RBW_CONFIG = Path.home() / "Library/Application Support/rbw/config.json"
DEFAULT_EMAIL = "rbw@local"
APPROVE_DESC = "VM sudo approval <vm-aarch64>"
APPROVE_HELPER = "__VM_TOUCHID_APPROVE__"
GIT_COMMIT_TOUCHID_HELPER = str(Path.home() / ".nix-profile/bin/gpg-touchid-commit-get-pin")
VM_GPG_SIGNING_FINGERPRINT = "071F6FE39FC26713930A702401E5F9A947FA8F5C"
APPROVE_CONTEXT = threading.local()

class PinentryFailure(RuntimeError):
    def __init__(self, lines):
        super().__init__("pinentry-touchid command failed")
        self.lines = lines


def load_rbw_email():
    try:
        cfg = json.loads(RBW_CONFIG.read_text())
    except Exception:
        return DEFAULT_EMAIL
    return cfg.get("email") or DEFAULT_EMAIL


def quote_assuan(value):
    escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
    return f"\"{escaped}\""


def decode_assuan_data(value):
    return urllib.parse.unquote(value)


class PinentrySession:
    def __init__(self, pinentry_program):
        self.proc = subprocess.Popen(
            [pinentry_program],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

    def __enter__(self):
        greeting = self.read_response()
        if greeting[-1].startswith("ERR"):
            raise PinentryFailure(greeting)
        return self

    def __exit__(self, exc_type, exc, tb):
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired as timeout_exc:
            self.proc.kill()
            self.proc.wait()
            if exc_type is None:
                raise RuntimeError("pinentry-touchid did not exit cleanly") from timeout_exc

    def read_response(self):
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if line == "":
                raise EOFError("pinentry-touchid closed stdout unexpectedly")
            lines.append(line)
            if line.startswith("OK") or line.startswith("ERR"):
                return lines

    def command(self, raw_command, require_ok=False):
        self.proc.stdin.write(raw_command)
        self.proc.stdin.flush()
        lines = self.read_response()
        if require_ok and lines[-1].startswith("ERR"):
            raise PinentryFailure(lines)
        return lines


def get_secret(pinentry_program):
    email = load_rbw_email()
    key_id = hashlib.sha1(email.encode("utf-8")).hexdigest()[:8].upper()
    keyinfo = f"rbw/{key_id}"
    desc = f"SETDESC \"Bitwarden RBW <{email}>\" ID {key_id}, Unlock the local database for 'rbw'"

    with PinentrySession(pinentry_program) as pinentry:
        pinentry.command("OPTION allow-external-password-cache\n", require_ok=True)
        pinentry.command(f"SETKEYINFO {keyinfo}\n", require_ok=True)
        pinentry.command(
            desc + "\n",
            require_ok=True,
        )
        response = pinentry.command("GETPIN\n")

    if response[-1].startswith("ERR"):
        raise PinentryFailure(response)

    chunks = []
    for line in response:
        if line.startswith("D "):
            chunks.append(decode_assuan_data(line[2:].rstrip("\n")))
    return "".join(chunks)


def normalize_prompt_text(value):
    if value is None:
        return None
    value = " ".join(str(value).split())
    return value or None


def display_command(command):
    command = normalize_prompt_text(command)
    if command is None:
        return None
    if len(command) > 120:
        return command[:117] + "..."
    return command


def approval_reason(metadata):
    app_name = normalize_prompt_text(metadata.get("invoking_app")) or "a process on the NixOS VM"
    command = display_command(metadata.get("command"))
    if command:
        return f"execute command '{command}' as administrator from {app_name}"
    return f"request administrator access from {app_name}"


def approve(pinentry_program):
    metadata = getattr(APPROVE_CONTEXT, "metadata", {})
    reason = approval_reason(metadata)
    result = subprocess.run(
        [APPROVE_HELPER, reason],
        capture_output=True,
        check=False,
        text=True,
    )
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    details = result.stderr.strip() or result.stdout.strip()
    raise RuntimeError(details or "vm-touchid-approve failed")


def gpg_signing_prompt(metadata):
    payload_kind = normalize_prompt_text(metadata.get("payload_kind")) or ""
    payload_subject = normalize_prompt_text(metadata.get("payload_subject")) or ""
    signer_name = normalize_prompt_text(metadata.get("signer_name")) or ""
    signer_email = normalize_prompt_text(metadata.get("signer_email")) or ""
    repo_name = normalize_prompt_text(metadata.get("repo_name")) or "repository"
    repo_branch = normalize_prompt_text(metadata.get("repo_branch")) or "detached"

    if payload_kind == "tag":
        subject_label = "Tag"
    elif payload_kind == "commit":
        subject_label = "Commit"
    else:
        raise RuntimeError(f"unsupported gpg payload kind: {payload_kind or 'unknown'}")

    signer = f"{signer_name} <{signer_email}>".strip()
    return "\n".join([
        f"Repo: {repo_name}",
        f"Branch: {repo_branch}",
        f"{subject_label}: {payload_subject}",
        f"Signer: {signer}",
    ])


def gpg_keychain_label(metadata):
    signer_name = normalize_prompt_text(metadata.get("signer_name")) or ""
    signer_email = normalize_prompt_text(metadata.get("signer_email")) or ""
    if not signer_name or not signer_email:
        raise RuntimeError("missing signer identity for gpg secret lookup")
    key_id = VM_GPG_SIGNING_FINGERPRINT[-16:].upper()
    return f"{signer_name} <{signer_email}> ({key_id})"


def get_gpg_secret(metadata):
    helper = os.environ.get("GPG_TOUCHID_COMMIT_HELPER") or GIT_COMMIT_TOUCHID_HELPER
    if not os.path.isfile(helper) or not os.access(helper, os.X_OK):
        raise RuntimeError(f"gpg touchid helper is unavailable: {helper}")

    env = os.environ.copy()
    env["GPG_TOUCHID_PAYLOAD_KIND"] = normalize_prompt_text(metadata.get("payload_kind")) or ""
    env["GPG_TOUCHID_PROMPT_DESC"] = gpg_signing_prompt(metadata)
    env["GPG_TOUCHID_KEYCHAIN_LABEL"] = gpg_keychain_label(metadata)
    result = subprocess.run(
        [helper],
        capture_output=True,
        check=False,
        env=env,
        text=True,
    )
    if result.returncode == 0:
        return {"ok": True, "secret": result.stdout}
    if result.returncode == 1:
        return {"ok": False, "cancelled": True}
    details = result.stderr.strip() or result.stdout.strip()
    return {"ok": False, "error": details or "gpg-touchid-commit-get-pin failed"}


def dispatch_request(request, pinentry_program):
    op = request.get("op")
    metadata = request.get("metadata") or {}

    if op == "approve":
        APPROVE_CONTEXT.metadata = metadata
        try:
            return {"ok": True, "approved": approve(pinentry_program)}
        finally:
            APPROVE_CONTEXT.metadata = {}
    if op == "get-gpg-secret":
        return get_gpg_secret(metadata)
    if op == "get-secret":
        return {"ok": True, "secret": get_secret(pinentry_program)}
    return {"ok": False, "error": f"unsupported op: {op}"}


def handle_connection(conn, pinentry_program):
    with conn:
        try:
            raw = b""
            while not raw.endswith(b"\n"):
                chunk = conn.recv(4096)
                if not chunk:
                    return
                raw += chunk
            request = json.loads(raw.decode("utf-8"))
            response = dispatch_request(request, pinentry_program)
        except PinentryFailure as exc:
            response = {
                "ok": False,
                "error": "pinentry-touchid command failed",
                "details": exc.lines,
            }
        except Exception as exc:
            response = {"ok": False, "error": str(exc)}

        try:
            conn.sendall((json.dumps(response) + "\n").encode("utf-8"))
        except BrokenPipeError:
            return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket-path", required=True)
    parser.add_argument("--pinentry-program", required=True)
    args = parser.parse_args()

    socket_path = Path(args.socket_path)
    socket_path.parent.mkdir(parents=True, exist_ok=True)
    if socket_path.exists():
        socket_path.unlink()

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))
    os.chmod(socket_path, 0o600)
    server.listen()

    try:
        while True:
            conn, _ = server.accept()
            thread = threading.Thread(
                target=handle_connection,
                args=(conn, args.pinentry_program),
                daemon=True,
            )
            thread.start()
    finally:
        server.close()
        if socket_path.exists():
            socket_path.unlink()


if __name__ == "__main__":
    main()
