{ ... }: { pkgs, ... }: let
  vmTouchIdBrokerSocket = "/Users/m/Library/Caches/vm-touchid-broker.sock";
  vmTouchIdRemoteSocket = "/home/m/.local/run/vm-touchid-broker.sock";
  vmTouchIdBridgeKey = "/Users/m/.ssh/id_ed25519_touchid_bridge_to_vm";
  vmTouchIdKnownHosts = "/Users/m/.ssh/known_hosts_vm_touchid_bridge";
  vmTouchIdVmKnownHostsEntry = "192.168.130.3 ${builtins.readFile ./vm-host-ssh-ed25519.pub}";
  vmTouchIdPinentry = "/opt/homebrew/opt/pinentry-touchid/bin/pinentry-touchid";
  vmTouchIdGpgCommitHelper = "/etc/profiles/per-user/m/bin/gpg-touchid-commit-get-pin";

  vmTouchIdApprove = pkgs.stdenvNoCC.mkDerivation {
    name = "vm-touchid-approve";
    dontUnpack = true;
    src = ./vm-touchid-approve.swift;
    plist = ./vm-touchid-approve.plist;
    buildCommand = ''
      set -euo pipefail

      app="$out/Applications/sudo NixOS VM.app"
      executable="$app/Contents/MacOS/sudo NixOS VM"
      mkdir -p "$app/Contents/MacOS" "$out/bin"

      cp "$plist" "$app/Contents/Info.plist"
      cp "$src" "$TMPDIR/vm-touchid-approve.swift"

      if ! [ -x /usr/bin/swiftc ]; then
        echo "vm-touchid-approve: swiftc not found; install Xcode Command Line Tools (docs/macbook.sh bootstraps them)." >&2
        exit 1
      fi
      /usr/bin/swiftc "$TMPDIR/vm-touchid-approve.swift" -o "$executable"
      ln -s "$executable" "$out/bin/vm-touchid-approve"
    '';
  };

  vmTouchIdBroker = pkgs.writeTextFile {
    name = "vm-touchid-broker";
    destination = "/bin/vm-touchid-broker";
    executable = true;
    text = builtins.replaceStrings
      [ "__VM_TOUCHID_APPROVE__" "__PYTHON_BIN__" ]
      [ "${vmTouchIdApprove}/Applications/sudo NixOS VM.app/Contents/MacOS/sudo NixOS VM" "${pkgs.python3}/bin/python3" ]
      (builtins.readFile ./vm-touchid-broker.py);
  };
in {
  homebrew = {
    taps = [ { name = "lujstn/tap"; trusted = true; } ];
    brews = [ { name = "pinentry-touchid"; trusted = true; } ];
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
      EnvironmentVariables = {
        GPG_TOUCHID_COMMIT_HELPER = vmTouchIdGpgCommitHelper;
      };
      StandardOutPath = "/tmp/rbw-pinentry-touchid-broker.log";
      StandardErrorPath = "/tmp/rbw-pinentry-touchid-broker.log";
    };
  };

  launchd.user.agents.vm-touchid-bridge-key = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          set -euo pipefail
          key="$HOME/.ssh/id_ed25519_touchid_bridge_to_vm"
          mkdir -p "$HOME/.ssh"
          if [ ! -f "$key" ]; then
            /usr/bin/ssh-keygen -q -t ed25519 -N "" -f "$key"
          fi
          chmod 600 "$key"
        ''
      ];
      RunAtLoad = true;
      StandardOutPath = "/tmp/vm-touchid-bridge-key.log";
      StandardErrorPath = "/tmp/vm-touchid-bridge-key.log";
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
            /usr/bin/ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/Users/m/.ssh/id_ed25519_touchid_bridge_to_vm -o UserKnownHostsFile=/Users/m/.ssh/known_hosts_vm_touchid_bridge -o GlobalKnownHostsFile=/dev/null -o StrictHostKeyChecking=yes m@192.168.130.3 \
              "mkdir -p /home/m/.local/run && rm -f ${vmTouchIdRemoteSocket}" >/dev/null 2>&1 || true
            /usr/bin/ssh -N \
              -F /dev/null \
              -o BatchMode=yes \
              -o IdentitiesOnly=yes \
              -o IdentityFile=/Users/m/.ssh/id_ed25519_touchid_bridge_to_vm \
              -o UserKnownHostsFile=/Users/m/.ssh/known_hosts_vm_touchid_bridge \
              -o GlobalKnownHostsFile=/dev/null \
              -o StreamLocalBindUnlink=yes \
              -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
              -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes \
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
}
