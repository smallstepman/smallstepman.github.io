{ pkgs, ... }: {
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
}
