{ den, generated, inputs, lib, ... }: {
  den.aspects.darwin-core = {
    includes = [
      ({ host, ... }:
        lib.optionalAttrs (host.class == "darwin") {
          darwin = { pkgs, ... }:
          let
            kubeconfigGeneratedDir = "/Users/m/.local/share/nix-config-generated";
            kubeconfigBitwardenItem = "orbstack-kubeconfig";
            kubeconfigTarget = "${kubeconfigGeneratedDir}/kubeconfig";
            vmTouchIdBrokerSocket = "/Users/m/Library/Caches/vm-touchid-broker.sock";
            vmTouchIdRemoteSocket = "/home/m/.local/run/vm-touchid-broker.sock";
            vmTouchIdPinentry = "/opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid";

            orbstackKubeconfigSync = pkgs.writeShellApplication {
              name = "orbstack-kubeconfig-sync";
              runtimeInputs = [ pkgs.coreutils pkgs.rbw ];
              text = ''
                set -euo pipefail
                umask 077

                mkdir -p ${kubeconfigGeneratedDir}
                tmp_kubeconfig=$(mktemp ${kubeconfigTarget}.XXXXXX)
                trap 'rm -f "$tmp_kubeconfig"' EXIT

                if ! rbw get ${kubeconfigBitwardenItem} > "$tmp_kubeconfig"; then
                  echo "orbstack-kubeconfig-sync: failed to fetch ${kubeconfigBitwardenItem} from Bitwarden" >&2
                  exit 1
                fi

                if [ ! -s "$tmp_kubeconfig" ]; then
                  echo "orbstack-kubeconfig-sync: empty kubeconfig from Bitwarden item ${kubeconfigBitwardenItem}" >&2
                  exit 1
                fi

                chmod 600 "$tmp_kubeconfig"
                if ! cmp -s "$tmp_kubeconfig" ${kubeconfigTarget} 2>/dev/null; then
                  mv "$tmp_kubeconfig" ${kubeconfigTarget}
                fi
              '';
            };

            vmTouchIdBroker = pkgs.writeTextFile {
              name = "vm-touchid-broker";
              destination = "/bin/vm-touchid-broker";
              executable = true;
              text = ''
                #!${pkgs.python3}/bin/python3
                import argparse
                import hashlib
                import json
                import os
                import socketserver
                import subprocess
                import urllib.parse
                from pathlib import Path

                RBW_CONFIG = Path.home() / "Library/Application Support/rbw/config.json"
                DEFAULT_EMAIL = "rbw@local"
                APPROVE_DESC = "VM sudo approval <vm-aarch64>"


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
                    desc = f"Bitwarden RBW <{email}> ID {key_id}, Unlock the local database for 'rbw'"

                    with PinentrySession(pinentry_program) as pinentry:
                        pinentry.command("OPTION allow-external-password-cache\n", require_ok=True)
                        pinentry.command(f"SETKEYINFO {keyinfo}\n", require_ok=True)
                        pinentry.command(
                            f"SETDESC {quote_assuan(desc)}\n",
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


                def approve(pinentry_program):
                    with PinentrySession(pinentry_program) as pinentry:
                        pinentry.command(
                            f"SETTITLE {quote_assuan('VM sudo approval')}\n",
                            require_ok=True,
                        )
                        pinentry.command(
                            f"SETDESC {quote_assuan(APPROVE_DESC)}\n",
                            require_ok=True,
                        )
                        pinentry.command(
                            f"SETPROMPT {quote_assuan('Touch ID')}\n",
                            require_ok=True,
                        )
                        response = pinentry.command("GETPIN\n")
                    return not response[-1].startswith("ERR")


                class ThreadedUnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
                    daemon_threads = True


                class Handler(socketserver.StreamRequestHandler):
                    def handle(self):
                        try:
                            raw = self.rfile.readline()
                            if not raw:
                                return
                            request = json.loads(raw.decode("utf-8"))
                            op = request.get("op")

                            if op == "approve":
                                response = {"ok": True, "approved": approve(self.server.pinentry_program)}
                            elif op == "get-secret":
                                response = {"ok": True, "secret": get_secret(self.server.pinentry_program)}
                            else:
                                response = {"ok": False, "error": f"unsupported op: {op}"}
                        except PinentryFailure as exc:
                            response = {
                                "ok": False,
                                "error": "pinentry-touchid command failed",
                                "details": exc.lines,
                            }
                        except Exception as exc:
                            response = {"ok": False, "error": str(exc)}

                        self.wfile.write((json.dumps(response) + "\n").encode("utf-8"))
                        self.wfile.flush()


                def main():
                    parser = argparse.ArgumentParser()
                    parser.add_argument("--socket-path", required=True)
                    parser.add_argument("--pinentry-program", required=True)
                    args = parser.parse_args()

                    socket_path = Path(args.socket_path)
                    socket_path.parent.mkdir(parents=True, exist_ok=True)
                    if socket_path.exists():
                        socket_path.unlink()

                    server = ThreadedUnixServer(str(socket_path), Handler)
                    server.pinentry_program = args.pinentry_program
                    os.chmod(socket_path, 0o600)

                    try:
                        server.serve_forever()
                    finally:
                        server.server_close()
                        if socket_path.exists():
                            socket_path.unlink()


                if __name__ == "__main__":
                    main()
              '';
            };
          in {
          imports = [ ../../../dotfiles/common/opencode/modules/darwin.nix ];

          system.stateVersion = 5;

          # This makes it work with the Determinate Nix installer.
          ids.gids.nixbld = 30000;

          # We use the determinate-nix installer which manages Nix for us,
          # so we don't want nix-darwin to do it.
          nix.enable = false;
          nix.extraOptions = ''
            experimental-features = nix-command flakes
            keep-outputs = true
            keep-derivations = true
          '';

          # Enable the Linux builder so we can run Linux builds on our Mac.
          nix.linux-builder = {
            enable = false;
            ephemeral = true;
            maxJobs = 4;
            config = ({ pkgs, ... }: {
              virtualisation = {
                cores = 6;
                darwin-builder = {
                  diskSize = 100 * 1024; # 100GB
                  memorySize = 32 * 1024; # 32GB
                };
              };

              environment.systemPackages = [
                pkgs.htop
              ];
            });
          };

          nix.settings.trusted-users = [ "@admin" ];

          # Determinate's nix.conf may not include nix.custom.conf; manage both.
          environment.etc."nix/nix.conf".text = ''
            build-users-group = nixbld
            !include /etc/nix/nix.custom.conf
          '';

          environment.etc."nix/nix.custom.conf".text = ''
            experimental-features = nix-command flakes
          '';

          # Make ad-hoc nixpkgs usage honor unfree defaults.
          environment.etc."nixpkgs/config.nix".text = ''
            { allowUnfree = true; }
          '';

          programs.zsh.enable = true;
          programs.zsh.shellInit = ''
            # Nix
            if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
              . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
            fi
            # End Nix
          '';

          programs.fish.enable = true;
          programs.fish.shellInit = ''
            # Nix
            if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
              source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
            end
            # End Nix
          '';

          environment.shells = with pkgs; [ bashInteractive zsh fish ];
          environment.systemPackages = with pkgs; [
            cachix
          ];

          # The user already exists via den identity, but nix-darwin still needs
          # these Darwin-specific fields to know the home directory and host SSH
          # trust configuration for host/guest integration.
            users.users.m = {
              home = "/Users/m";
              openssh.authorizedKeys.keyFiles = [
                (generated.requireFile "mac-host-authorized-keys")
              ];
            };

          services.openssh.enable = true;
          services.openssh.extraConfig = ''
            # Only listen on the VMware host/guest interface so sshd is not reachable
            # from other network interfaces (Wi-Fi, Ethernet, etc.).
            ListenAddress 192.168.130.1
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitRootLogin no
            X11Forwarding no
            AllowUsers m
          '';

          security.pam.services.sudo_local = {
            touchIdAuth = true;
            watchIdAuth = true;
            reattach = true;
          };

          homebrew.enable = true;
          homebrew.taps = [
            "lujstn/tap"
          ];
          homebrew.casks = [
            "activitywatch"
            "launchcontrol"
            # Nix-provided s3fs on Darwin links against the macFUSE runtime.
            "macfuse"

            "mullvad-vpn"
            "orbstack"
          ];
          homebrew.brews = [
            "gnupg"
            "pinentry-touchid"
            "gromgit/fuse/s3fs-mac"
          ];
          homebrew.masApps = {
            "Tailscale" = 1475387142;
          };

          launchd.user.agents.uniclip = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  set -euo pipefail
                  /bin/wait4path /nix/store
                  export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
                  UNICLIP_PASSWORD="$(${pkgs.rbw}/bin/rbw get uniclip-password)"
                  if [ -z "$UNICLIP_PASSWORD" ]; then
                    echo "uniclip: empty password from rbw" >&2
                    exit 1
                  fi
                  export UNICLIP_PASSWORD
                  exec ${pkgs.uniclip}/bin/uniclip --secure --bind 192.168.130.1 -p 53701
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/uniclip-server.log";
              StandardErrorPath = "/tmp/uniclip-server.log";
            };
          };

          launchd.user.agents.orbstack-kubeconfig-sync = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  set -euo pipefail
                  /bin/wait4path /nix/store
                  export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
                  exec ${orbstackKubeconfigSync}/bin/orbstack-kubeconfig-sync
                ''
              ];
              RunAtLoad = true;
              StartInterval = 300;
              StandardOutPath = "/tmp/orbstack-kubeconfig-sync.log";
              StandardErrorPath = "/tmp/orbstack-kubeconfig-sync.log";
            };
          };

          launchd.user.agents.rbw-pinentry-touchid-broker = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  set -euo pipefail
                  /bin/wait4path /nix/store
                  exec ${vmTouchIdBroker}/bin/vm-touchid-broker \
                    --socket-path ${vmTouchIdBrokerSocket} \
                    --pinentry-program ${vmTouchIdPinentry}
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              LimitLoadToSessionType = "Aqua";
              ProcessType = "Interactive";
              StandardOutPath = "/tmp/rbw-pinentry-touchid-broker.log";
              StandardErrorPath = "/tmp/rbw-pinentry-touchid-broker.log";
            };
          };

          launchd.user.agents.vm-touchid-broker-tunnel = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  set -euo pipefail
                  while true; do
                    while [ ! -S ${vmTouchIdBrokerSocket} ]; do
                      sleep 1
                    done
                    /usr/bin/ssh-keygen -R "192.168.130.3" >/dev/null 2>&1 || true
                    /usr/bin/ssh -o StrictHostKeyChecking=accept-new m@192.168.130.3 \
                      "mkdir -p /home/m/.local/run && rm -f ${vmTouchIdRemoteSocket}" >/dev/null 2>&1 || true
                    /usr/bin/ssh -N \
                      -o StreamLocalBindUnlink=yes \
                      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                      -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                      -R ${vmTouchIdRemoteSocket}:${vmTouchIdBrokerSocket} \
                      m@192.168.130.3
                    sleep 5
                  done
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/vm-touchid-broker-tunnel.log";
              StandardErrorPath = "/tmp/vm-touchid-broker-tunnel.log";
            };
          };

          launchd.user.agents.openwebui-tunnel = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  while true; do
                    /usr/bin/ssh-keygen -R "192.168.130.3" >/dev/null 2>&1 || true
                    /usr/bin/ssh -N \
                      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                      -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                      -R 18080:127.0.0.1:8080 m@192.168.130.3
                    sleep 5
                  done
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/openwebui-tunnel.log";
              StandardErrorPath = "/tmp/openwebui-tunnel.log";
            };
          };

          launchd.user.agents.activitywatch-tunnel = {
            serviceConfig = {
              ProgramArguments = [
                "/bin/bash" "-c"
                ''
                  while true; do
                    /usr/bin/ssh-keygen -R "192.168.130.3" >/dev/null 2>&1 || true
                    /usr/bin/ssh -N \
                      -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                      -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                      -R 5600:127.0.0.1:5600 m@192.168.130.3
                    sleep 5
                  done
                ''
              ];
              RunAtLoad = true;
              KeepAlive = true;
              StandardOutPath = "/tmp/activitywatch-tunnel.log";
              StandardErrorPath = "/tmp/activitywatch-tunnel.log";
            };
          };

          launchd.user.agents.activitywatch-sync-aw-to-calendar = {
            serviceConfig = {
              ProgramArguments = [
                "/usr/bin/osascript"
                "-l"
                "JavaScript"
                "/Users/m/.config/activitywatch/scripts/synchronize.js"
              ];
              RunAtLoad = true;
              StartInterval = 1800;
              WorkingDirectory = "/Users/m/.config/activitywatch/scripts";
              StandardOutPath = "/tmp/aw-sync-aw-to-calendar.out.log";
              StandardErrorPath = "/tmp/aw-sync-aw-to-calendar.err.log";
            };
          };

          launchd.user.agents.activitywatch-sync-ios-screentime-to-aw =
            let
              awImportScreentimeSrc = pkgs.applyPatches {
                name = "aw-import-screentime-src";
                src = inputs.aw-import-screentime-src;
                patches = [ ../../../patches/aw-import-screentime.patch ];
              };
            in {
              serviceConfig = {
                ProgramArguments = [
                  "/Applications/LaunchControl.app/Contents/MacOS/fdautil"
                  "exec"
                  "/bin/bash"
                  "/Users/m/.config/activitywatch/scripts/run_sync.sh"
                ];
                EnvironmentVariables = {
                  AW_IMPORT_SRC = "${awImportScreentimeSrc}";
                  PATH = "/etc/profiles/per-user/m/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin";
                };
                RunAtLoad = true;
                StartInterval = 3600;
                WorkingDirectory = "/Users/m/.config/activitywatch/scripts";
                StandardOutPath = "/tmp/aw-sync-ios-screentime-to-aw.out.log";
                StandardErrorPath = "/tmp/aw-sync-ios-screentime-to-aw.err.log";
              };
            };

          launchd.user.agents.activitywatch-bucketize-aw-and-sync-to-calendar = {
            serviceConfig = {
              ProgramArguments = [
                "/usr/bin/osascript"
                "-l"
                "JavaScript"
                "/Users/m/.config/activitywatch/scripts/bucketize.js"
              ];
              RunAtLoad = true;
              StartInterval = 900;
              WorkingDirectory = "/Users/m/.config/activitywatch/scripts";
              StandardOutPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.out.log";
              StandardErrorPath = "/tmp/aw-bucketize-aw-and-sync-to-calendar.err.log";
            };
          };
        };

        homeManager = { pkgs, ... }: {
          home.packages = [
            pkgs.ghostty-bin
            pkgs.skhd
            pkgs.cachix
            pkgs.gettext
            pkgs.sentry-cli
            pkgs.rsync
            pkgs.sshpass
            pkgs.keycastr
          ];

          xdg.configFile = {
            "wezterm/wezterm.lua".text = builtins.readFile ../../../dotfiles/by-host/darwin/wezterm.lua;
            "activitywatch/scripts" = {
              source = ../../../dotfiles/by-host/darwin/activitywatch;
              recursive = true;
            };
          };
        };
      })
    ];
  };
}
