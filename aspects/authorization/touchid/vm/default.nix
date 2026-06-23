{ config, lib, pkgs, generated, ... }: let
  vmTouchIdUserBrokerSocket = "/home/m/.local/run/vm-touchid-broker.sock";
  vmTouchIdUserBridgeKey = "/home/m/.ssh/id_ed25519_touchid_bridge_to_host";
  vmTouchIdUserKnownHosts = "/home/m/.ssh/known_hosts_touchid_bridge";
  vmTouchIdSudoBrokerSocket = "/run/vm-touchid-sudo-broker.sock";
  macTouchIdBrokerSocket = "/Users/m/Library/Caches/vm-touchid-broker.sock";
  vmTouchIdSudoBridgeKey = "/var/lib/vm-touchid-sudo-bridge/id_ed25519";
  vmTouchIdSudoKnownHosts = "/var/lib/vm-touchid-sudo-bridge/known_hosts";
  macTouchIdKnownHostsEntry = "192.168.130.1 ${builtins.readFile (generated.requireFile "mac-host-ssh-ed25519.pub")}";

  mkRbwPinentryTouchIdBridge = pkgs: pkgs.substituteAll {
    name = "vm-gpg-touchid-pinentry-bridge";
    dir = "/bin";
    src = ./vm-pinentry-bridge.py;
    isExecutable = true;
    inherit vmTouchIdUserBrokerSocket;
    python3 = "${pkgs.python3}";
    wayprompt = "${pkgs.wayprompt}";
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
        ssh -N -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
          -o IdentityFile=${vmTouchIdUserBridgeKey} \
          -o UserKnownHostsFile=${vmTouchIdUserKnownHosts} \
          -o GlobalKnownHostsFile=/dev/null -o StreamLocalBindUnlink=yes \
          -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
          -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes \
          -L "$local_socket:$remote_socket" m@192.168.130.1
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
      import json, os, socket, sys
      BROKER_SOCKET = "${vmTouchIdSudoBrokerSocket}"
      TIMEOUT = 10.0
      def main():
          with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as c:
              c.settimeout(TIMEOUT); c.connect(BROKER_SOCKET)
              c.sendall(json.dumps({"op": "sudo-approve"}).encode() + b"\n")
              r = bytearray()
              while not r.endswith(b"\n"): r.extend(c.recv(4096))
          sys.exit(0 if json.loads(r.decode()).get("ok") else 1)
      if __name__ == "__main__": main()
    '';
  };

  mkVmTouchIdSudoBrokerTunnel = pkgs: pkgs.writeShellApplication {
    name = "vm-touchid-sudo-broker-tunnel";
    runtimeInputs = [ pkgs.coreutils pkgs.openssh ];
    text = ''
      set -euo pipefail; umask 077
      local_socket="${vmTouchIdSudoBrokerSocket}"
      remote_socket="${macTouchIdBrokerSocket}"
      mkdir -p "$(dirname "$local_socket")"
      while true; do
        rm -f "$local_socket"
        ssh -N -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
          -o IdentityFile=${vmTouchIdSudoBridgeKey} \
          -o UserKnownHostsFile=${vmTouchIdSudoKnownHosts} \
          -o GlobalKnownHostsFile=/dev/null -o StreamLocalBindUnlink=yes \
          -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
          -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes \
          -L "$local_socket:$remote_socket" m@192.168.130.1
        sleep 5
      done
    '';
  };
in {
  den.aspects.authorization.touchid.vm = {
    nixos = { config, pkgs, lib, ... }:
      let
        vmTouchIdSudoBridge = mkVmTouchIdSudoBridge pkgs;
        vmTouchIdSudoBrokerTunnel = mkVmTouchIdSudoBrokerTunnel pkgs;
      in {
        systemd.services.vm-touchid-sudo-bridge-key = {
          description = "Create the dedicated root SSH key for the macOS Touch ID sudo bridge";
          wantedBy = [ "multi-user.target" ];
          before = [ "vm-touchid-sudo-broker-tunnel.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.writeShellScript "vm-touchid-sudo-bridge-key" ''
              set -euo pipefail; umask 077
              key="${vmTouchIdSudoBridgeKey}"; known_hosts="${vmTouchIdSudoKnownHosts}"
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
            Restart = "always"; RestartSec = 5;
          };
        };

        users.users.m = {
          extraGroups = [ "lxd" ];
          openssh.authorizedKeys.keyFiles = [
            (generated.requireFile "host-authorized-keys")
            (generated.requireFile "touchid-bridge-mac-to-vm.pub")
          ];
        };

        environment.systemPackages = [ vmTouchIdSudoBridge ];
      };

    homeManager = { pkgs, lib, ... }:
      let
        rbwPinentryTouchIdBrokerTunnel = mkRbwPinentryTouchIdBrokerTunnel pkgs;
        vmGpgTouchIdPinentry = mkRbwPinentryTouchIdBridge pkgs;
      in {
        services.gpg-agent = {
          defaultCacheTtl = 1;
          maxCacheTtl = 1;
          pinentry.package = vmGpgTouchIdPinentry;
          extraConfig = ''
            pinentry-program ${vmGpgTouchIdPinentry}/bin/vm-gpg-touchid-pinentry-bridge
          '';
        };

        home.activation.ensureVmTouchIdBridgeUserKey =
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            key="$HOME/.ssh/id_ed25519_touchid_bridge_to_host"
            run mkdir -p "$HOME/.ssh"
            if [ ! -f "$key" ]; then
              run ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$key"
            fi
            run chmod 600 "$key"
          '';
        
        home.file.".ssh/${builtins.baseNameOf vmTouchIdUserKnownHosts}".text =
          macTouchIdKnownHostsEntry;

        systemd.user.services.rbw-pinentry-touchid-broker-tunnel = {
          Unit = {
            Description = "Forward the macOS Touch ID rbw broker socket into the VM";
            After = [ "default.target" "network-online.target" ];
            Wants = [ "network-online.target" ];
          };
          Service = {
            Type = "simple";
            ExecStart = "${rbwPinentryTouchIdBrokerTunnel}/bin/rbw-pinentry-touchid-broker-tunnel";
            Restart = "always"; RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
  };
}
