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
            name = "rbw-pinentry-touchid-bridge-fallback";
            destination = "/bin/rbw-pinentry-touchid-bridge";
            executable = true;
            text = ''
              #!${pkgs.python3}/bin/python3
              import json
              import socket
              import subprocess
              import sys
              import urllib.parse

              BROKER_SOCKET = "${vmTouchIdUserBrokerSocket}"
              LOCAL_FALLBACK = "${pkgs.wayprompt}/bin/pinentry-wayprompt"
              BROKER_CONNECT_TIMEOUT_SECONDS = 2.0
              BROKER_RESPONSE_TIMEOUT_SECONDS = 60.0
              OK = "OK\n"


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


              def broker_get_secret():
                  with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                      client.settimeout(BROKER_CONNECT_TIMEOUT_SECONDS)
                      client.connect(BROKER_SOCKET)
                      client.settimeout(BROKER_RESPONSE_TIMEOUT_SECONDS)
                      client.sendall(b'{"op":"get-secret"}\n')

                      response = bytearray()
                      while not response.endswith(b"\n"):
                          chunk = client.recv(4096)
                          if not chunk:
                              raise EOFError("broker closed connection unexpectedly")
                          response.extend(chunk)

                  payload = json.loads(response.decode("utf-8"))
                  if not payload.get("ok"):
                      raise RuntimeError(payload.get("error") or "broker request failed")

                  secret = payload.get("secret")
                  if not isinstance(secret, str) or secret == "":
                      raise RuntimeError("broker returned an empty secret")
                  return secret


              def activate_fallback(history):
                  child = PinentryProcess(LOCAL_FALLBACK)
                  for raw in history:
                      child.command(raw)
                  return child


              def emit(lines):
                  for line in lines:
                      sys.stdout.write(line)
                  sys.stdout.flush()


              def main():
                  fallback = None
                  history = []

                  sys.stdout.write("OK Pleased to meet you, broker touchid fallback ready\n")
                  sys.stdout.flush()

                  try:
                      for raw in sys.stdin:
                          if fallback is not None:
                              emit(fallback.command(raw))
                              continue

                          if raw == "GETPIN\n":
                              try:
                                  secret = broker_get_secret()
                              except Exception:
                                  fallback = activate_fallback(history)
                                  emit(fallback.command(raw))
                                  continue

                              sys.stdout.write(f"D {encode_data(secret)}\n")
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
            programs.git.settings.gpg.program = "${pkgs.gnupg}/bin/gpg";
            programs.git.package = repairingGit;

            services.gpg-agent.pinentry.package = pkgs.pinentry-tty;
            services.gpg-agent.extraConfig = "allow-preset-passphrase";

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
