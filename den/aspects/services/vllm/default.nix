{ pkgs, ... }: let
  composeYamlSrc = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/noonghunna/club-3090/refs/heads/master/models/qwen3.6-27b/vllm/compose/dual/autoround-int4/fp8-mtp.yml";
    hash = "sha256-csN3hKbD7YNdA1xKXj1lblSBXKHp0+vkJyXMz8UYSAo=";
  };

  composeYaml = pkgs.runCommand "patched-compose.yml" {
    src = composeYamlSrc;
  } ''
    sed -z 's|\([[:space:]]*\)- driver: nvidia\n\([[:space:]]*\)count: all\n[[:space:]]*capabilities: \[gpu\]|\1- driver: cdi\n\2capabilities: [gpu]\n\2device_ids:\n\2  - nvidia.com/gpu=all|' "$src" > "$out"
  '';

  dcgmExporterImage = "nvcr.io/nvidia/k8s/dcgm-exporter:4.4.1-4.6.0-ubuntu22.04";
in {
  den.aspects.services.vllm = {
    nixos = { config, pkgs, lib, ... }: {
      systemd.services.club-3090 = {
        description = "vLLM Dual RTX 3090 (Qwen 3.6 27B)";
        after = [ "network.target" "docker.service" "docker.socket" "nvidia-power-limits.service" ];
        requires = [ "docker.service" "nvidia-power-limits.service" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ docker curl ];
        environment = {
          MODEL_DIR = "/home/m/models";
          CLUB3090_DEFAULT_QWEN3_6_27B = "vllm/dual";
          PORT = "8000";
        };
        preStart = ''
          install -m 644 ${composeYaml} /var/lib/vllm-dual-3090/compose.yml
        '';
        script = ''
          exec docker compose -f /var/lib/vllm-dual-3090/compose.yml up --remove-orphans
        '';
        preStop = ''
          if [ -f /var/lib/vllm-dual-3090/compose.yml ]; then
            docker compose -f /var/lib/vllm-dual-3090/compose.yml down
          fi
        '';
        serviceConfig = {
          Type = "exec";
          Restart = "on-failure";
          RestartSec = "10s";
          TimeoutStartSec = "15min";
          StateDirectory = "vllm-dual-3090";
        };
      };

      virtualisation.oci-containers.containers.dcgm-exporter = {
        image = dcgmExporterImage;
        ports = [ "9400:9400" ];
        extraOptions = [ "--gpus=all" ];
      };
    };
  };
}
