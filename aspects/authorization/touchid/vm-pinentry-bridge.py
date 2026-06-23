#!@python3@/bin/python3
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import urllib.parse

BROKER_SOCKET = "@vmTouchIdUserBrokerSocket@"
LOCAL_FALLBACK = "@wayprompt@/bin/pinentry-wayprompt"
BROKER_CONNECT_TIMEOUT_SECONDS = 2.0
BROKER_RESPONSE_TIMEOUT_SECONDS = 60.0
OK = "OK\n"


class BrokerCancelled(Exception):
    pass


class PinentryProcess:
    def __init__(self, program):
        self.proc = subprocess.Popen(
            [program],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self.read_response()

    def read_response(self):
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if line == "":
                raise EOFError("fallback pinentry closed stdout unexpectedly")
            lines.append(line)
            if line.startswith("OK") or line.startswith("ERR"):
                return lines

    def command(self, raw_command):
        self.proc.stdin.write(raw_command)
        self.proc.stdin.flush()
        return self.read_response()

    def close(self):
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except Exception:
            pass
        return self.proc.wait()


def encode_data(value):
    return urllib.parse.quote(value, safe="")


def metadata_path_from_tty(tty_name):
    if not tty_name:
        return None

    cache_home = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache"))
    tty_key = re.sub(r"[^A-Za-z0-9._-]", "_", tty_name)
    return cache_home / "gpg-touchid-signing-prompts" / f"{tty_key}.metadata"


def load_signing_context_from_path(metadata_path):
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
    if payload_kind not in {"commit", "tag"}:
        return None

    if not any(
        pairs.get(key)
        for key in (
            "payload_subject",
            "signer_name",
            "signer_email",
            "repo_name",
            "repo_branch",
            "tag_name",
        )
    ):
        return None

    return {
        "payload_kind": payload_kind,
        "payload_subject": pairs.get("payload_subject") or "",
        "tag_name": pairs.get("tag_name") or "",
        "signer_name": pairs.get("signer_name") or "",
        "signer_email": pairs.get("signer_email") or "",
        "repo_name": pairs.get("repo_name") or "",
        "repo_branch": pairs.get("repo_branch") or "detached",
    }


def load_signing_context(tty_name):
    return load_signing_context_from_path(metadata_path_from_tty(tty_name))


def load_signing_context_from_owner(owner_value, proc_root=Path("/proc")):
    owner_pid = owner_value.split("/", 1)[0].strip()
    if not owner_pid or not owner_pid.isdigit():
        return None

    environ_path = proc_root / owner_pid / "environ"
    try:
        raw_environ = environ_path.read_bytes()
    except OSError:
        return None

    environ = {}
    for entry in raw_environ.split(b"\0"):
        if not entry or b"=" not in entry:
            continue
        key, value = entry.split(b"=", 1)
        try:
            environ[key.decode("utf-8")] = value.decode("utf-8")
        except UnicodeDecodeError:
            continue

    metadata_path = environ.get("GPG_TOUCHID_METADATA_PATH")
    if metadata_path:
        context = load_signing_context_from_path(Path(metadata_path))
        if context is not None:
            return context

    gpg_tty = environ.get("GPG_TTY")
    if gpg_tty:
        return load_signing_context(gpg_tty)

    return None


def is_rbw_desc(command):
    return "local database for 'rbw'" in command or "Bitwarden" in command


def broker_request_payload(session_kind, signing_context):
    if session_kind == "rbw":
        return {"op": "get-secret"}
    if session_kind == "gpg-signing" and signing_context is not None:
        return {
            "op": "get-gpg-secret",
            "metadata": signing_context,
        }
    raise RuntimeError(f"unsupported broker session kind: {session_kind}")


def broker_cancelled(payload):
    if payload.get("cancelled") is True:
        return True

    for key in ("status", "error", "code"):
        value = payload.get(key)
        if not isinstance(value, str):
            continue
        normalized = value.strip().lower().replace("_", "-")
        if normalized in {
            "cancelled",
            "user-cancelled",
            "operation-cancelled",
        }:
            return True

    return False


def broker_get_secret(session_kind, signing_context=None):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(BROKER_CONNECT_TIMEOUT_SECONDS)
        client.connect(BROKER_SOCKET)
        client.settimeout(BROKER_RESPONSE_TIMEOUT_SECONDS)
        request = broker_request_payload(session_kind, signing_context)
        client.sendall(json.dumps(request).encode("utf-8") + b"\n")

        response = bytearray()
        while not response.endswith(b"\n"):
            chunk = client.recv(4096)
            if not chunk:
                raise EOFError("broker closed connection unexpectedly")
            response.extend(chunk)

    payload = json.loads(response.decode("utf-8"))
    if payload.get("ok"):
        secret = payload.get("secret")
        if not isinstance(secret, str) or secret == "":
            raise RuntimeError("broker returned an empty secret")
        return secret

    if broker_cancelled(payload):
        raise BrokerCancelled()

    if not payload.get("ok"):
        raise RuntimeError(payload.get("error") or "broker request failed")

    raise RuntimeError("broker request failed")


def activate_fallback(history):
    child = PinentryProcess(LOCAL_FALLBACK)
    for raw in history:
        child.command(raw)
    return child


def emit(lines):
    for line in lines:
        sys.stdout.write(line)
    sys.stdout.flush()


def write_assuan_secret(secret):
    sys.stdout.write(f"D {encode_data(secret)}\n")
    sys.stdout.write(OK)
    sys.stdout.flush()


def write_assuan_cancel():
    sys.stdout.write("ERR 83886179 Operation cancelled <Pinentry>\n")
    sys.stdout.flush()


def main():
    fallback = None
    history = []
    signing_context = None
    session_kind = None
    owner_value = None

    sys.stdout.write("OK Pleased to meet you, broker touchid pinentry ready\n")
    sys.stdout.flush()

    try:
        for raw in sys.stdin:
            if fallback is not None:
                emit(fallback.command(raw))
                continue

            if raw.startswith("OPTION ttyname="):
                tty_name = raw.split("=", 1)[1].rstrip("\n")
                signing_context = load_signing_context(tty_name)
                if signing_context is not None:
                    session_kind = "gpg-signing"
                history.append(raw)
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw.startswith("OPTION owner="):
                owner_value = raw.split("=", 1)[1].rstrip("\n")
                if signing_context is None:
                    signing_context = load_signing_context_from_owner(owner_value)
                    if signing_context is not None:
                        session_kind = "gpg-signing"
                history.append(raw)
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw.startswith("SETDESC ") and is_rbw_desc(raw):
                session_kind = "rbw"
                history.append(raw)
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw == "GETPIN\n":
                if session_kind is None and signing_context is None and owner_value is not None:
                    signing_context = load_signing_context_from_owner(owner_value)
                    if signing_context is not None:
                        session_kind = "gpg-signing"

                if session_kind == "gpg-signing":
                    try:
                        secret = broker_get_secret(session_kind, signing_context)
                    except BrokerCancelled:
                        write_assuan_cancel()
                        continue
                    except Exception:
                        fallback = activate_fallback(history)
                        emit(fallback.command(raw))
                        continue

                    write_assuan_secret(secret)
                    continue

                if session_kind == "rbw":
                    try:
                        secret = broker_get_secret(session_kind)
                    except BrokerCancelled:
                        write_assuan_cancel()
                        continue
                    except Exception:
                        fallback = activate_fallback(history)
                        emit(fallback.command(raw))
                        continue

                    write_assuan_secret(secret)
                    continue

                fallback = activate_fallback(history)
                emit(fallback.command(raw))
                continue

            if raw == "GETINFO flavor\n":
                sys.stdout.write("D broker-touchid\n")
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw == "GETINFO version\n":
                sys.stdout.write("D 0.0.0\n")
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw == "GETINFO ttyinfo\n":
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw == "GETINFO pid\n":
                sys.stdout.write(f"D {os.getpid()}\n")
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            if raw == "BYE\n":
                sys.stdout.write(OK)
                sys.stdout.flush()
                return 0

            if (
                raw.startswith("OPTION ")
                or raw.startswith("SETDESC ")
                or raw.startswith("SETTITLE ")
                or raw.startswith("SETPROMPT ")
                or raw.startswith("SETKEYINFO ")
                or raw.startswith("SETOK ")
                or raw.startswith("SETCANCEL ")
                or raw.startswith("SETNOTOK ")
                or raw.startswith("SETERROR ")
            ):
                history.append(raw)
                sys.stdout.write(OK)
                sys.stdout.flush()
                continue

            fallback = activate_fallback(history)
            emit(fallback.command(raw))
    finally:
        if fallback is not None:
            raise SystemExit(fallback.close())

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
