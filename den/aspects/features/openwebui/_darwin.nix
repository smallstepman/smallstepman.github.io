{ pkgs, ... }: {
  launchd.user.agents.openwebui = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          /bin/wait4path /nix/store
          mkdir -p "/Users/m/.local/state/open-webui"/{static,data,hf_home,transformers_home}
          export PATH=${pkgs.uv}/bin:$PATH
          export STATIC_DIR="/Users/m/.local/state/open-webui/static"
          export DATA_DIR="/Users/m/.local/state/open-webui/data"
          export HF_HOME="/Users/m/.local/state/open-webui/hf_home"
          export SENTENCE_TRANSFORMERS_HOME="/Users/m/.local/state/open-webui/transformers_home"
          export WEBUI_URL="http://localhost:8080"
          export SCARF_NO_ANALYTICS=True
          export DO_NOT_TRACK=True
          export ANONYMIZED_TELEMETRY=False
          cd "/Users/m/.local/state/open-webui"
          exec ${pkgs.uv}/bin/uvx --python 3.11 open-webui@latest serve --host 127.0.0.1 --port 8080
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/openwebui.log";
      StandardErrorPath = "/tmp/openwebui.log";
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
}
