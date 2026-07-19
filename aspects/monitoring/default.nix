{ pkgs, lib, ... }: {
  den.aspects.monitoring = {
    nixos = { config, pkgs, ... }:
    let
      grafanaSecretKeyDir = "/var/lib/grafana-secret";
      grafanaSecretKeyFile = "${grafanaSecretKeyDir}/secret_key";
    in {
      users.users.alloy = {
        isSystemUser = true;
        group = "alloy";
        extraGroups = [ "docker" ];
      };
      users.groups.alloy = {};

      services.journald.extraConfig = ''
        Storage=persistent
        SystemMaxUse=20G
        RuntimeMaxUse=2G
        MaxRetentionSec=90day
      '';

      services.prometheus.exporters.node = {
        enable = true;
        port = 9100;
        enabledCollectors = [
          "systemd" "cpu" "meminfo" "diskstats" "filesystem"
          "netdev" "loadavg" "stat" "time" "thermal_zone" "hwmon"
        ];
        extraFlags = [ "--collector.textfile.directory=/var/lib/node_exporter" ];
      };
      services.prometheus.exporters.smartctl = { enable = true; port = 9633; };
      services.smartd.enable = true;

      services.prometheus = {
        enable = true;
        port = 9090;
        retentionTime = "30d";
        scrapeConfigs = [
          { job_name = "baremetal_linux"; static_configs = [{ targets = [ "127.0.0.1:9100" ]; }]; }
          { job_name = "vllm"; static_configs = [{ targets = [ "127.0.0.1:8000" ]; }]; }
          { job_name = "dcgm"; static_configs = [{ targets = [ "127.0.0.1:9400" ]; }]; }
          { job_name = "prometheus"; static_configs = [{ targets = [ "127.0.0.1:9090" ]; }]; }
          { job_name = "smartctl"; static_configs = [{ targets = [ "127.0.0.1:9633" ]; }]; }
        ];
      };

      services.loki = {
        enable = true;
        configFile = pkgs.writeText "loki-config.yaml" ''
          auth_enabled: false
          server:
            http_listen_port: 3100
          ingester:
            lifecycler:
              address: 127.0.0.1
          analytics:
            reporting_enabled: false
        '';
      };

      services.alloy = {
        enable = true;
        extraFlags = ["--disable-reporting"];
      };

      environment.etc."alloy/config.alloy".text = ''
        loki.source.docker "docker_logs" {
          host     = "unix:///var/run/docker.sock"
          forward_to = [loki.write.local.receiver]
        }
        loki.source.journal "system_logs" {
          max_age = "168h"
          labels = { host = "jimi"; source = "journald"; }
          forward_to = [loki.write.local.receiver]
        }
        loki.write "local" {
          endpoint { url = "http://127.0.0.1:3100/loki/api/v1/push" }
        }
      '';

      systemd.services.grafana-secret-key = {
        description = "Generate Grafana's local secret key";
        requiredBy = [ "grafana.service" ];
        before = [ "grafana.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          set -euo pipefail
          key=${lib.escapeShellArg grafanaSecretKeyFile}
          ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g grafana ${lib.escapeShellArg grafanaSecretKeyDir}
          if [ ! -s "$key" ]; then
            tmp="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${grafanaSecretKeyDir}/.secret_key.XXXXXX"})"
            trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
            ${pkgs.openssl}/bin/openssl rand -hex 32 > "$tmp"
            ${pkgs.coreutils}/bin/chown root:grafana "$tmp"
            ${pkgs.coreutils}/bin/chmod 0440 "$tmp"
            ${pkgs.coreutils}/bin/mv "$tmp" "$key"
            trap - EXIT
          fi
          ${pkgs.coreutils}/bin/chown root:grafana "$key"
          ${pkgs.coreutils}/bin/chmod 0440 "$key"
        '';
      };

      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "0.0.0.0";
            http_port = 3001;
          };
          security.secret_key = "$__file{${grafanaSecretKeyFile}}";
        };
        provision = {
          enable = true;
          datasources.settings.datasources = [
            { name = "Prometheus"; type = "prometheus"; url = "http://127.0.0.1:9090"; isDefault = true; }
            { name = "Loki"; type = "loki"; url = "http://127.0.0.1:3100"; }
          ];
        };
      };

      systemd.services.grafana = {
        requires = [ "grafana-secret-key.service" ];
        after = [ "grafana-secret-key.service" ];
      };
    };
  };
}
