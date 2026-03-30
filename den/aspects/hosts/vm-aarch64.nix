{ den, generated, inputs, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      den.aspects.linux-core
      den.aspects.secrets
      den.aspects.linux-desktop
      den.aspects.vmware
      den.provides.hostname

      ({ host, ... }:
        let
          vmTouchIdUserBrokerSocket = "/home/m/.local/run/vm-touchid-broker.sock";
          vmTouchIdSudoBrokerSocket = "/run/vm-touchid-sudo-broker.sock";
          macTouchIdBrokerSocket = "/Users/m/Library/Caches/vm-touchid-broker.sock";
          vmTouchIdUserBridgeKey = "/home/m/.ssh/id_ed25519_touchid_bridge_to_host";
          vmTouchIdSudoBridgeKey = "/var/lib/vm-touchid-sudo-bridge/id_ed25519";
          vmTouchIdUserKnownHosts = "/home/m/.ssh/known_hosts_touchid_bridge";
          vmTouchIdSudoKnownHosts = "/var/lib/vm-touchid-sudo-bridge/known_hosts";
          macTouchIdKnownHostsEntry = "192.168.130.1 ${builtins.readFile (generated.requireFile "mac-host-ssh-ed25519.pub")}";

          mkRbwPinentryTouchIdBridge = pkgs: pkgs.writeTextFile {
            name = "vm-gpg-touchid-pinentry-bridge";
            destination = "/bin/vm-gpg-touchid-pinentry-bridge";
            executable = true;
            text = ''
              #!${pkgs.python3}/bin/python3
              import json
              import os
              from pathlib import Path
              import re
              import socket
              import subprocess
              import sys
              import urllib.parse

              BROKER_SOCKET = "${vmTouchIdUserBrokerSocket}"
              LOCAL_FALLBACK = "${pkgs.wayprompt}/bin/pinentry-wayprompt"
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


              def load_signing_context(tty_name):
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

                          if raw.startswith("SETDESC ") and is_rbw_desc(raw):
                              session_kind = "rbw"
                              history.append(raw)
                              sys.stdout.write(OK)
                              sys.stdout.flush()
                              continue

                          if raw == "GETPIN\n":
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
            '';
          };

          mkRbwPinentryTouchIdBrokerTunnel = pkgs: pkgs.writeShellApplication {
            name = "rbw-pinentry-touchid-broker-tunnel";
            runtimeInputs = [ pkgs.coreutils pkgs.openssh ];
            text = ''
              set -euo pipefail

              local_socket="${vmTouchIdUserBrokerSocket}"
              remote_socket="${macTouchIdBrokerSocket}"

              mkdir -p "$(dirname "$local_socket")"

              while true; do
                rm -f "$local_socket"
                ssh -N \
                  -F /dev/null \
                  -o BatchMode=yes \
                  -o IdentitiesOnly=yes \
                  -o IdentityFile=${vmTouchIdUserBridgeKey} \
                  -o UserKnownHostsFile=${vmTouchIdUserKnownHosts} \
                  -o GlobalKnownHostsFile=/dev/null \
                  -o StreamLocalBindUnlink=yes \
                  -o ServerAliveInterval=30 \
                  -o ServerAliveCountMax=3 \
                  -o ExitOnForwardFailure=yes \
                  -o StrictHostKeyChecking=yes \
                  -L "$local_socket:$remote_socket" \
                  m@192.168.130.1
                sleep 5
              done
            '';
          };

          mkVmTouchIdSudoBridge = pkgs: pkgs.writeTextFile {
            name = "vm-touchid-sudo-bridge";
            destination = "/bin/vm-touchid-sudo-bridge";
            executable = true;
            text = ''
              #!${pkgs.python3}/bin/python3
              import json
              import os
              import socket

              BROKER_SOCKET = "${vmTouchIdSudoBrokerSocket}"
              BROKER_CONNECT_TIMEOUT_SECONDS = 2.0
              BROKER_RESPONSE_TIMEOUT_SECONDS = 60.0


              def proc_name(pid):
                  try:
                      with open(f"/proc/{pid}/comm", "r", encoding="utf-8") as handle:
                          return handle.read().strip() or None
                  except OSError:
                      return None


              def parent_pid(pid):
                  try:
                      with open(f"/proc/{pid}/status", "r", encoding="utf-8") as handle:
                          for line in handle:
                              if line.startswith("PPid:"):
                                  return int(line.split()[1])
                  except (OSError, ValueError, IndexError):
                      return None
                  return None


              def invoking_app():
                  ignored = {
                      "sudo",
                      "sudoedit",
                      "vm-touchid-sudo-bridge",
                      "python",
                      "python3",
                  }
                  pid = os.getppid()
                  seen = set()

                  while pid and pid > 1 and pid not in seen:
                      seen.add(pid)
                      name = proc_name(pid)
                      if name and name not in ignored:
                          return name
                      pid = parent_pid(pid)

                  return None


              def pam_metadata():
                  return {
                      "service": os.getenv("PAM_SERVICE"),
                      "type": os.getenv("PAM_TYPE"),
                      "user": os.getenv("PAM_USER"),
                      "invoking_user": os.getenv("PAM_RUSER") or os.getenv("SUDO_USER"),
                      "invoking_app": invoking_app(),
                      "tty": os.getenv("PAM_TTY"),
                      "command": os.getenv("SUDO_COMMAND"),
                  }


              def broker_approve():
                  request = {
                      "op": "approve",
                      "metadata": {
                          key: value
                          for key, value in pam_metadata().items()
                          if value not in (None, "")
                      },
                  }

                  with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                      client.settimeout(BROKER_CONNECT_TIMEOUT_SECONDS)
                      client.connect(BROKER_SOCKET)
                      client.settimeout(BROKER_RESPONSE_TIMEOUT_SECONDS)
                      client.sendall((json.dumps(request) + "\n").encode("utf-8"))

                      response = bytearray()
                      while not response.endswith(b"\n"):
                          chunk = client.recv(4096)
                          if not chunk:
                              raise EOFError("broker closed connection unexpectedly")
                          response.extend(chunk)

                  payload = json.loads(response.decode("utf-8"))
                  return bool(payload.get("ok") and payload.get("approved"))


              def main():
                  try:
                      return 0 if broker_approve() else 1
                  except Exception:
                      return 1


              if __name__ == "__main__":
                  raise SystemExit(main())
            '';
          };

          mkVmTouchIdSudoBrokerTunnel = pkgs: pkgs.writeShellApplication {
            name = "vm-touchid-sudo-broker-tunnel";
            runtimeInputs = [ pkgs.coreutils pkgs.openssh ];
            text = ''
              set -euo pipefail
              umask 077

              local_socket="${vmTouchIdSudoBrokerSocket}"
              remote_socket="${macTouchIdBrokerSocket}"

              mkdir -p "$(dirname "$local_socket")"

              while true; do
                rm -f "$local_socket"
                ssh -N \
                  -F /dev/null \
                  -o IdentityFile=${vmTouchIdSudoBridgeKey} \
                  -o BatchMode=yes \
                  -o IdentitiesOnly=yes \
                  -o UserKnownHostsFile=${vmTouchIdSudoKnownHosts} \
                  -o GlobalKnownHostsFile=/dev/null \
                  -o StreamLocalBindUnlink=yes \
                  -o ServerAliveInterval=30 \
                  -o ServerAliveCountMax=3 \
                  -o ExitOnForwardFailure=yes \
                  -o StrictHostKeyChecking=yes \
                  -L "$local_socket:$remote_socket" \
                  m@192.168.130.1
                sleep 5
              done
            '';
          };
        in {
        nixos = { config, pkgs, lib, ... }:
          let
            vmTouchIdSudoBridge = mkVmTouchIdSudoBridge pkgs;
            vmTouchIdSudoBrokerTunnel = mkVmTouchIdSudoBrokerTunnel pkgs;
          in {
          imports = [
            inputs.disko.nixosModules.disko
          ];

          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.allowUnsupportedSystem = true;

          boot.initrd.availableKernelModules = [ "uhci_hcd" "ahci" "xhci_pci" "nvme" "usbhid" "sr_mod" ];
          boot.initrd.kernelModules = [ ];
          boot.kernelModules = [ ];
          boot.extraModulePackages = [ ];
          swapDevices = [ ];

          disko.devices = {
            disk.main = {
              device = lib.mkDefault "/dev/nvme0n1";
              type = "disk";
              content = {
                type = "gpt";
                partitions = {
                  ESP = {
                    size = "500M";
                    type = "EF00";
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                      mountOptions = [ "umask=0077" ];
                    };
                  };
                  root = {
                    size = "100%";
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/";
                    };
                  };
                };
              };
            };
          };

          boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

          fileSystems."/nixos-config" = {
            fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
            device = ".host:/nixos-config";
            options = [
              "umask=22"
              "uid=1000"
              "gid=1000"
              "allow_other"
              "auto_unmount"
              "defaults"
            ];
          };

          fileSystems."/nixos-generated" = {
            fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
            device = ".host:/nixos-generated";
            options = [
              "umask=22"
              "uid=1000"
              "gid=1000"
              "allow_other"
              "auto_unmount"
              "defaults"
            ];
          };

          fileSystems."/Users/m/Projects" = {
            fsType = "fuse./run/current-system/sw/bin/vmhgfs-fuse";
            device = ".host:/Projects";
            options = [
              "umask=22"
              "uid=1000"
              "gid=1000"
              "allow_other"
              "auto_unmount"
              "defaults"
            ];
          };

          networking.interfaces.enp2s0.useDHCP = true;

          sops.hostPubKey = lib.removeSuffix "\n"
            (generated.readFile "vm-age-pubkey");

          networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];

          systemd.services.openwebui-local-proxy = {
            description = "Expose tunneled Open WebUI on localhost:80";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:18080";
              Restart = "always";
              RestartSec = 1;
            };
          };

          systemd.services.vm-touchid-sudo-bridge-key = {
            description = "Create the dedicated root SSH key for the macOS Touch ID sudo bridge";
            wantedBy = [ "multi-user.target" ];
            before = [ "vm-touchid-sudo-broker-tunnel.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.writeShellScript "vm-touchid-sudo-bridge-key" ''
                set -euo pipefail
                umask 077
                key="${vmTouchIdSudoBridgeKey}"
                known_hosts="${vmTouchIdSudoKnownHosts}"
                mkdir -p "$(dirname "$key")"
                if [ ! -f "$key" ]; then
                  ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$key"
                fi
                chmod 600 "$key"
                printf '%s' ${lib.escapeShellArg macTouchIdKnownHostsEntry} > "$known_hosts"
                chmod 600 "$known_hosts"
              ''}";
            };
          };

          systemd.services.vm-touchid-sudo-broker-tunnel = {
            description = "Expose the macOS Touch ID sudo broker on a root-owned runtime socket";
            wantedBy = [ "multi-user.target" ];
            wants = [ "network-online.target" "vm-touchid-sudo-bridge-key.service" ];
            after = [ "network-online.target" "vm-touchid-sudo-bridge-key.service" ];
            serviceConfig = {
              ExecStart = "${vmTouchIdSudoBrokerTunnel}/bin/vm-touchid-sudo-broker-tunnel";
              Restart = "always";
              RestartSec = 5;
            };
          };

          users.users.m = {
            extraGroups = [ "lxd" ];
            openssh.authorizedKeys.keyFiles = [
              (generated.requireFile "host-authorized-keys")
              (generated.requireFile "touchid-bridge-mac-to-vm.pub")
            ];
          };

          environment.systemPackages = [
            vmTouchIdSudoBridge
          ];

          den.secrets.rbwPinentryPackage = mkRbwPinentryTouchIdBridge pkgs;
        };

        homeManager = { pkgs, lib, ... }:
          let
            vmGitSigningKey = "071F6FE39FC26713930A702401E5F9A947FA8F5C";
            rbwPinentryTouchIdBrokerTunnel = mkRbwPinentryTouchIdBrokerTunnel pkgs;
            vmGpgTouchIdPinentry = mkRbwPinentryTouchIdBridge pkgs;

            vmGitSigningWrapper = pkgs.writeShellScriptBin "vm-gpg-touchid-signing" ''
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
                  */.git)
                    VM_GPG_TOUCHID_REPO_NAME=$(basename "$(dirname "$common_dir")")
                    ;;
                  ?*)
                    VM_GPG_TOUCHID_REPO_NAME=$(basename "$common_dir")
                    ;;
                esac

                if [ -z "$VM_GPG_TOUCHID_REPO_NAME" ]; then
                  repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
                  if [ -n "$repo_root" ]; then
                    VM_GPG_TOUCHID_REPO_NAME=$(basename "$repo_root")
                  fi
                fi

                VM_GPG_TOUCHID_REPO_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
                if [ -z "$VM_GPG_TOUCHID_REPO_BRANCH" ]; then
                  VM_GPG_TOUCHID_REPO_BRANCH="detached"
                fi
              }

              vm_gpg_touchid_cleanup_file() {
                local path="''${1:-}"

                if [ -n "$path" ] && [ -e "$path" ]; then
                  rm -f -- "$path"
                fi
              }

              vm_gpg_touchid_metadata_path_for_tty() {
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

              vm_gpg_touchid_write_signing_metadata_file() {
                local payload="$1"
                local tty_name="$2"
                local metadata_file

                if [ -z "$tty_name" ]; then
                  return 1
                fi

                vm_gpg_touchid_parse_signing_payload "$payload"
                vm_gpg_touchid_derive_repo_context

                metadata_file=$(vm_gpg_touchid_metadata_path_for_tty "$tty_name") || return 1

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

              vm_gpg_touchid_exec_gpg_with_metadata() {
                local gpg_bin="''${GPG_TOUCHID_GPG_BIN:-${pkgs.gnupg}/bin/gpg}"
                local payload_file=""
                local metadata_file=""
                local payload=""
                local tty_name=""
                local tracked_pid=""
                local cleanup_watcher_pid=""

                cleanup() {
                  vm_gpg_touchid_cleanup_file "$metadata_file"
                  vm_gpg_touchid_cleanup_file "$payload_file"
                }

                spawn_cleanup_watcher() {
                  local watched_pid="$1"
                  local watched_metadata="$2"
                  local watched_payload="$3"

                  (
                    while kill -0 "$watched_pid" 2>/dev/null; do
                      sleep 1
                    done
                    [ -n "$watched_metadata" ] && rm -f -- "$watched_metadata"
                    [ -n "$watched_payload" ] && rm -f -- "$watched_payload"
                  ) >/dev/null 2>&1 &
                  printf '%s\n' "$!"
                }

                trap cleanup EXIT HUP INT TERM

                payload_file=$(mktemp "''${TMPDIR:-/tmp}/vm-gpg-touchid-signing-payload.XXXXXX")
                cat >"$payload_file"
                payload=$(cat "$payload_file")
                tty_name="''${GPG_TTY:-}"
                if [ -z "$tty_name" ]; then
                  tty_name=$(tty 2>/dev/null || true)
                fi
                if [ -n "$tty_name" ] && [ "$tty_name" != "not a tty" ]; then
                  metadata_file=$(vm_gpg_touchid_write_signing_metadata_file "$payload" "$tty_name" || true)
                fi

                trap - EXIT HUP INT TERM
                tracked_pid=$$
                cleanup_watcher_pid=$(spawn_cleanup_watcher "$tracked_pid" "$metadata_file" "$payload_file")
                GPG_TOUCHID_METADATA_PATH="$metadata_file" exec "$gpg_bin" "$@" <"$payload_file"

                # exec only returns if launching gpg fails.
                status=$?
                if [ -n "$cleanup_watcher_pid" ]; then
                  kill "$cleanup_watcher_pid" 2>/dev/null || true
                  wait "$cleanup_watcher_pid" 2>/dev/null || true
                fi
                cleanup
                return "$status"
              }

              vm_gpg_touchid_exec_gpg_with_metadata "$@"
            '';

            kubePassthroughBroker = pkgs.writeShellApplication {
              name = "kubectl-passthrough-broker";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gawk
                pkgs.kubectl
              ];
              text = ''
                set -euo pipefail

                source_kubeconfig="/nixos-generated/kubeconfig"
                local_kubeconfig="$HOME/.kube/config"
                state_dir="$HOME/.local/state/kubectl-passthrough"
                ports_file="$state_dir/ports.tsv"
                tunnels_dir="$state_dir/tunnels"
                last_source_hash=""

                declare -A brokered_clusters=()
                declare -A brokered_remotes=()
                declare -A desired_tunnels=()

                log() {
                  printf 'kubectl-passthrough: %s\n' "$*" >&2
                }

                cluster_hash() {
                  printf '%s' "$1" | sha256sum | awk '{print $1}'
                }

                brokerable_server() {
                  case "$1" in
                    https://127.0.0.1:*|https://localhost:*|https://192.168.130.1:*)
                      return 0
                      ;;
                    *)
                      return 1
                      ;;
                  esac
                }

                remote_port_from_server() {
                  local server="$1"
                  local port="''${server##*:}"
                  port="''${port%%/*}"
                  case "$port" in
                    "")
                      return 1
                      ;;
                    *[!0-9]*)
                      return 1
                      ;;
                    *)
                      printf '%s\n' "$port"
                      ;;
                  esac
                }

                port_for_cluster() {
                  local cluster_name="$1"
                  local existing_port next_port

                  if [ -f "$ports_file" ]; then
                    existing_port=$(awk -F '\t' -v cluster="$cluster_name" '$1 == cluster { print $2; exit }' "$ports_file" || true)
                    if [ -n "$existing_port" ]; then
                      printf '%s\n' "$existing_port"
                      return 0
                    fi
                    next_port=$(awk -F '\t' 'BEGIN { max = 46442 } NF >= 2 && $2 + 0 > max { max = $2 + 0 } END { print max + 1 }' "$ports_file")
                  else
                    next_port=46443
                  fi

                  printf '%s\t%s\n' "$cluster_name" "$next_port" >> "$ports_file"
                  printf '%s\n' "$next_port"
                }

                clear_broker_state() {
                  brokered_clusters=()
                  brokered_remotes=()
                  desired_tunnels=()
                }

                stop_stale_tunnels() {
                  local pidfile hash pid remote_port local_port

                  for pidfile in "$tunnels_dir"/*.pid; do
                    [ -e "$pidfile" ] || continue
                    hash=$(basename "$pidfile" .pid)
                    if [ -z "''${desired_tunnels[$hash]+x}" ]; then
                      read -r pid remote_port local_port < "$pidfile" || true
                      if [ -n "''${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
                        log "stopping stale tunnel $hash"
                        kill "$pid" 2>/dev/null || true
                        wait "$pid" 2>/dev/null || true
                      fi
                      rm -f "$pidfile" "$tunnels_dir/$hash.log"
                    fi
                  done
                }

                sync_local_kubeconfig() {
                  local cluster_rows cluster_name server_url remote_port local_port cluster_hash tmp_kubeconfig

                  cluster_rows=$(kubectl --kubeconfig "$source_kubeconfig" config view --raw -o jsonpath='{range .clusters[*]}{.name}{"\t"}{.cluster.server}{"\n"}{end}')

                  clear_broker_state
                  tmp_kubeconfig="$state_dir/kubeconfig.new"
                  cp "$source_kubeconfig" "$tmp_kubeconfig"

                  while IFS=$'\t' read -r cluster_name server_url; do
                    [ -n "$cluster_name" ] || continue
                    [ -n "$server_url" ] || continue
                    if ! brokerable_server "$server_url"; then
                      continue
                    fi
                    if ! remote_port=$(remote_port_from_server "$server_url"); then
                      log "skipping cluster $cluster_name with unsupported server $server_url"
                      continue
                    fi
                    local_port=$(port_for_cluster "$cluster_name")
                    cluster_hash=$(cluster_hash "$cluster_name")
                    desired_tunnels["$cluster_hash"]=1
                    brokered_clusters["$cluster_name"]="$local_port"
                    brokered_remotes["$cluster_name"]="$remote_port"
                    kubectl --kubeconfig "$tmp_kubeconfig" config set-cluster "$cluster_name" --server "https://127.0.0.1:$local_port" >/dev/null
                  done <<EOF
$cluster_rows
EOF

                  chmod 600 "$tmp_kubeconfig"
                  mv "$tmp_kubeconfig" "$local_kubeconfig"
                }

                reconcile_tunnels() {
                  local cluster_name cluster_hash pidfile log_file pid stored_remote_port stored_local_port local_port remote_port

                  mkdir -p "$tunnels_dir"

                  for cluster_name in "''${!brokered_clusters[@]}"; do
                    local_port="''${brokered_clusters[$cluster_name]}"
                    remote_port="''${brokered_remotes[$cluster_name]}"
                    cluster_hash=$(cluster_hash "$cluster_name")
                    pidfile="$tunnels_dir/$cluster_hash.pid"
                    log_file="$tunnels_dir/$cluster_hash.log"

                    if [ -f "$pidfile" ]; then
                      read -r pid stored_remote_port stored_local_port < "$pidfile" || true
                      if [ -n "''${pid:-}" ] && kill -0 "$pid" 2>/dev/null && [ "''${stored_remote_port:-}" = "$remote_port" ] && [ "''${stored_local_port:-}" = "$local_port" ]; then
                        continue
                      fi
                      if [ -n "''${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
                        log "restarting tunnel for $cluster_name"
                        kill "$pid" 2>/dev/null || true
                        wait "$pid" 2>/dev/null || true
                      fi
                    fi

                    log "starting tunnel for $cluster_name at 127.0.0.1:$local_port -> localhost:$remote_port"
                    /run/current-system/sw/bin/ssh -N -T \
                      -o StrictHostKeyChecking=accept-new \
                      -o ServerAliveInterval=30 \
                      -o ServerAliveCountMax=3 \
                      -o ExitOnForwardFailure=yes \
                      -L "127.0.0.1:''${local_port}:localhost:''${remote_port}" \
                      m@192.168.130.1 >> "$log_file" 2>&1 &
                    pid=$!
                    printf '%s %s %s\n' "$pid" "$remote_port" "$local_port" > "$pidfile"
                  done

                  stop_stale_tunnels
                }

                mkdir -p "$HOME/.kube" "$state_dir" "$tunnels_dir"
                shopt -s nullglob

                while true; do
                  if [ -f "$source_kubeconfig" ]; then
                    current_source_hash=$(sha256sum "$source_kubeconfig" | awk '{print $1}')
                    if [ "$current_source_hash" != "$last_source_hash" ]; then
                      if sync_local_kubeconfig; then
                        last_source_hash="$current_source_hash"
                        reconcile_tunnels
                      else
                        log "failed to sync kubeconfig; keeping existing tunnels"
                      fi
                    else
                      reconcile_tunnels
                    fi
                  else
                    pidfiles=("$tunnels_dir"/*.pid)
                    if [ -n "$last_source_hash" ] || [ -f "$local_kubeconfig" ] || [ "''${#pidfiles[@]}" -gt 0 ]; then
                      log "source kubeconfig missing; clearing local config and tunnels"
                      clear_broker_state
                      rm -f "$local_kubeconfig"
                      reconcile_tunnels
                    fi
                    last_source_hash=""
                  fi
                  sleep 5
                done
              '';
            };

            gpgPresetPassphraseLogin = pkgs.writeShellScriptBin "gpg-preset-passphrase-login" ''
              set -euo pipefail

              if ! passphrase="$(${pkgs.rbw}/bin/rbw get gpg-password-nixos-macbook-vm)"; then
                echo "gpg-preset-passphrase-login: failed to read gpg-password-nixos-macbook-vm from rbw" >&2
                exit 1
              fi

              if [ -z "$passphrase" ]; then
                echo "gpg-preset-passphrase-login: empty passphrase from rbw" >&2
                exit 1
              fi

              mapfile -t keygrips < <(
                ${pkgs.gnupg}/bin/gpg --batch --with-colons --with-keygrip --list-secret-keys ${vmGitSigningKey} \
                  | ${pkgs.gawk}/bin/awk -F: '$1 == "grp" && $10 != "" { print $10 }'
              )
              if [ "''${#keygrips[@]}" -eq 0 ]; then
                echo "gpg-preset-passphrase-login: failed to resolve keygrip for ${vmGitSigningKey}" >&2
                exit 1
              fi

              ${pkgs.gnupg}/bin/gpg-connect-agent /bye >/dev/null
              for keygrip in "''${keygrips[@]}"; do
                printf '%s' "$passphrase" | ${pkgs.gnupg}/bin/gpg-preset-passphrase --preset "$keygrip"
              done
            '';

            repairSharedGitFileMode = pkgs.writeShellScriptBin "repair-shared-git-filemode" ''
              set -euo pipefail

              git_bin=${pkgs.git}/bin/git

              repair_repo() {
                local root="$1"

                case "$root" in
                  /nixos-config|/Users/m/Projects|/Users/m/Projects/*) ;;
                  *) return 0 ;;
                esac

                "$git_bin" -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
                "$git_bin" -C "$root" config core.fileMode false
                "$git_bin" -C "$root" submodule foreach --quiet 'git config core.fileMode false' 2>/dev/null || true
              }

              if [ "$#" -eq 0 ]; then
                repair_repo /nixos-config
                exit 0
              fi

              for repo in "$@"; do
                repair_repo "$repo"
              done
            '';

            repairingGit = pkgs.writeShellScriptBin "git" ''
              set -euo pipefail

              git_bin=${pkgs.git}/bin/git
              realpath_bin=${pkgs.coreutils}/bin/realpath
              repair_bin=${repairSharedGitFileMode}/bin/repair-shared-git-filemode

              resolve_workdir() {
                local dir="$PWD"
                local work_tree=""
                local git_dir_only=0

                while [ "$#" -gt 0 ]; do
                  case "$1" in
                    -C)
                      [ "$#" -ge 2 ] || break
                      case "$2" in
                        /*) dir=$("$realpath_bin" -m "$2") ;;
                        *) dir=$("$realpath_bin" -m "$dir/$2") ;;
                      esac
                      shift 2
                      ;;
                    --work-tree)
                      [ "$#" -ge 2 ] || break
                      case "$2" in
                        /*) work_tree=$("$realpath_bin" -m "$2") ;;
                        *) work_tree=$("$realpath_bin" -m "$dir/$2") ;;
                      esac
                      shift 2
                      ;;
                    --work-tree=*)
                      case "''${1#*=}" in
                        /*) work_tree=$("$realpath_bin" -m "''${1#*=}") ;;
                        *) work_tree=$("$realpath_bin" -m "$dir/''${1#*=}") ;;
                      esac
                      shift
                      ;;
                    --git-dir)
                      [ "$#" -ge 2 ] || break
                      git_dir_only=1
                      shift 2
                      ;;
                    --git-dir=*)
                      git_dir_only=1
                      shift
                      ;;
                    --)
                      break
                      ;;
                    -c|--exec-path|--namespace|--super-prefix|--config-env)
                      [ "$#" -ge 2 ] || break
                      shift 2
                      ;;
                    --exec-path=*|--namespace=*|--super-prefix=*|--config-env=*)
                      shift
                      ;;
                    -*)
                      shift
                      ;;
                    *)
                      break
                      ;;
                  esac
                done

                if [ -n "$work_tree" ]; then
                  dir="$work_tree"
                elif [ "$git_dir_only" -eq 1 ]; then
                  return 1
                fi

                printf '%s\n' "$dir"
              }

              if workdir=$(resolve_workdir "$@"); then
                if root=$("$git_bin" -C "$workdir" rev-parse --show-toplevel 2>/dev/null); then
                  "$repair_bin" "$root"
                fi
              fi

              exec "$git_bin" "$@"
            '';

            opencode = import ../../../dotfiles/common/opencode/modules/common.nix;
          in {
            home.packages = [
              pkgs.docker-client
              gpgPresetPassphraseLogin
            ];

            home.sessionVariables = {
              GENERATED_INPUT_DIR = "/nixos-generated";
              DOCKER_CONTEXT = "host-mac";
            };

            programs.git.signing.key = vmGitSigningKey;
            programs.git.settings.gpg.program = "${vmGitSigningWrapper}/bin/vm-gpg-touchid-signing";
            programs.git.package = repairingGit;

            services.gpg-agent.pinentry.package = vmGpgTouchIdPinentry;
            services.gpg-agent.extraConfig = ''
              allow-preset-passphrase
              pinentry-program ${vmGpgTouchIdPinentry}/bin/vm-gpg-touchid-pinentry-bridge
            '';

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

            home.file.".ssh/${builtins.baseNameOf vmTouchIdUserKnownHosts}".text = macTouchIdKnownHostsEntry;

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

            home.activation.ensureVmTouchIdBridgeUserKey =
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                key="$HOME/.ssh/id_ed25519_touchid_bridge_to_host"
                run mkdir -p "$HOME/.ssh"
                if [ ! -f "$key" ]; then
                  run ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$key"
                fi
                run chmod 600 "$key"
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

            systemd.user.services.gpg-preset-passphrase-login = {
              Unit = {
                Description = "Preset GPG signing passphrase on login";
                After = [ "default.target" "rbw-config.service" ];
                Wants = [ "rbw-config.service" ];
              };
              Service = {
                Type = "oneshot";
                ExecStart = "${gpgPresetPassphraseLogin}/bin/gpg-preset-passphrase-login";
                Restart = "on-failure";
                RestartSec = 30;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.rbw-pinentry-touchid-broker-tunnel = {
              Unit = {
                Description = "Forward the macOS Touch ID rbw broker socket into the VM";
                After = [ "default.target" "network-online.target" ];
                Wants = [ "network-online.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${rbwPinentryTouchIdBrokerTunnel}/bin/rbw-pinentry-touchid-broker-tunnel";
                Restart = "always";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.opencode-serve = {
              Unit = {
                Description = "OpenCode stable server (serve mode)";
                After = [ "default.target" ];
              };
              Service = {
                Type = "simple";
                ExecStartPre = "${pkgs.opencode}/bin/opencode models --refresh";
                ExecStart = "${pkgs.opencode}/bin/opencode serve --mdns --mdns-domain ${opencode.stableMdnsDomain} --port ${toString opencode.stablePort}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.opencode-web = {
              Unit = {
                Description = "OpenCode web interface";
                After = [ "default.target" ];
              };
              Service = {
                Type = "simple";
                ExecStartPre = "${pkgs.opencode}/bin/opencode models --refresh";
                ExecStart = "${pkgs.opencode}/bin/opencode web --mdns --mdns-domain ${opencode.webMdnsDomain} --port ${toString opencode.webPort}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };

            systemd.user.services.uniclip = {
              Unit = {
                Description = "Uniclip clipboard client (direct connection to macOS server)";
                After = [ "graphical-session.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${pkgs.writeShellScript "uniclip-client" ''
                  set -euo pipefail
                  export XDG_RUNTIME_DIR=/run/user/$(id -u)
                  export PATH=${lib.makeBinPath [ pkgs.wl-clipboard ]}:$PATH
                  if [ -S "$XDG_RUNTIME_DIR/wayland-1" ]; then
                    export WAYLAND_DISPLAY=wayland-1
                  elif [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
                    export WAYLAND_DISPLAY=wayland-0
                  else
                    echo "uniclip: no wayland socket found in $XDG_RUNTIME_DIR" >&2
                    exit 1
                  fi
                  if [ ! -r /run/secrets/uniclip/password ]; then
                    echo "uniclip: /run/secrets/uniclip/password is missing" >&2
                    exit 1
                  fi
                  UNICLIP_PASSWORD="$(cat /run/secrets/uniclip/password)"
                  if [ -z "$UNICLIP_PASSWORD" ]; then
                    echo "uniclip: empty password from /run/secrets/uniclip/password" >&2
                    exit 1
                  fi
                  export UNICLIP_PASSWORD
                  exec ${pkgs.uniclip}/bin/uniclip --secure 192.168.130.1:53701
                ''}";
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "graphical-session.target" ];
            };

            systemd.user.services.kubectl-passthrough = {
              Unit = {
                Description = "Broker OrbStack Kubernetes tunnels through stable localhost ports";
                After = [ "default.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = "${kubePassthroughBroker}/bin/kubectl-passthrough-broker";
                Restart = "always";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };
          };
      })
    ];
  };
}
