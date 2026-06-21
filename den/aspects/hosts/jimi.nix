{ den, lib, inputs, ... }: {
  den.aspects.jimi = {
    nixos = { config, pkgs, lib, ... }:
let
  composeYamlSrc = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/noonghunna/club-3090/refs/heads/master/models/qwen3.6-27b/vllm/compose/dual/autoround-int4/fp8-mtp.yml";
    hash = "sha256-csN3hKbD7YNdA1xKXj1lblSBXKHp0+vkJyXMz8UYSAo=";
  };

  composeYaml = pkgs.runCommand "patched-compose.yml" {
    src = composeYamlSrc;
  } ''
    sed -z 's|\([[:space:]]*\)- driver: nvidia\n\([[:space:]]*\)count: all\n[[:space:]]*capabilities: \[gpu\]|\1- driver: cdi\n\2capabilities: [gpu]\n\2device_ids:\n\2  - nvidia.com/gpu=all|' "$src" > "$out"
  '';
in
    {
      imports = [
        inputs.disko.nixosModules.disko
        inputs.unattended-installer.nixosModules.diskoInstaller
      ];

      # Timezone and locale
      time.timeZone = "UTC";
      i18n.defaultLocale = "en_US.UTF-8";

      # Nix settings
      nix.settings = {
        auto-optimise-store = true;
        max-jobs = 16;
        cores = 16;
      };
      nix.gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };

      # ── NixOS goes on the SMALLER disk ─────────────────────────
      disko.devices.disk.main = {
        device = "/dev/disk/by-id/nvme-KBG40ZNV512G_KIOXIA_70KPG29NQBV1";  # 476.9G KIOXIA (stable per drive identity)
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2G";
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
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/root" = { mountpoint = "/"; };
                  "/home" = { mountpoint = "/home"; };
                  "/nix" = { mountpoint = "/nix"; };
                  "/var" = { mountpoint = "/var"; };
                };
              };
            };
          };
        };
      };

      fileSystems."/mnt/ubuntu" = {
        device = "/dev/ubuntu-vg/ubuntu-lv";
        fsType = "ext4";
        options = [ "ro" ];
      };

      boot.kernel.sysctl = {
        "kernel.panic_on_oops" = 1;
        "kernel.sysrq" = 1;
      };
      boot.zfs.forceImportRoot = false;
      boot.loader.systemd-boot.enable = lib.mkForce true;
      boot.loader.systemd-boot.configurationLimit = 20; # nix generations
      boot.loader.efi.canTouchEfiVariables = lib.mkForce true;
      boot.loader.grub = {
        enable = lib.mkForce false;
        device = lib.mkForce "nodev"; # W trybie UEFI wyłączamy przypisywanie do konkretnego urządzenia dyskowego
      };

      # WiFi - TP-Link Archer T2U Plus (RTL8821AU via rtw88)
      # Use kernel 6.18 which has rtw88_8821au support (6.12.93 does not)
      boot.kernelPackages = pkgs.linuxPackages_6_18;
      boot.initrd.kernelModules = [ "rtw88_core" "rtw88_usb" "rtw88_88xxa" "rtw88_8821a" "rtw88_8821au" ];

      networking.hostName = "jimi";
      networking.networkmanager = {
        enable = true;
        ensureProfiles.profiles = {
          "Preconfigured-WiFi" = {
            connection = {
              id = "Siema";
              type = "wifi";
              autoconnect = true;
            };
            wifi = {
              ssid = "Siema";
              mode = "infrastructure";
            };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "p79sqKgG2DyRlh"; 
            };
          };
        };
      };


      # SSH - key-only login
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
      ];

      users.users.root.hashedPassword = "$6$fhySpewi.hTKt.1D$nfheFtKH358q9dKSgrHGsgfzIsot4MgHQiT/A4YMB3hLe00CxTiiGr94qJZGsmFMOIbVMxqGq5emtrWJFWEwD1";

      # Tailscale - tunnel all services, no open ports
      services.tailscale = {
        enable = true;
        useRoutingFeatures = "both";
        extraUpFlags = [ "--advertise-exit-node" ];
      };

      # ── NVIDIA Driver (Headless) ──────────────────────────────────────
      services.xserver.videoDrivers = [ "nvidia" ];  # ← CRITICAL: gates all NVIDIA support

      hardware.graphics.enable = true;  # Required for /run/opengl-driver

      hardware.nvidia = {
        package = config.boot.kernelPackages.nvidiaPackages.stable;
        open = true;                     # NVIDIA explicitly recommends using the open-source GPU kernel modules (nvidia-open) for the RTX 3090
        nvidiaSettings = false;          # No GUI needed
        nvidiaPersistenced = true;       # Daemon keeps GPU state alive without X11
        modesetting.enable = true;       # DRM KMS (defaults to true for >=535 anyway)
      };

      # ── NVIDIA Container Toolkit ──────────────────────────────────────
      hardware.nvidia-container-toolkit.enable = true;
      virtualisation.docker = {
        enable = true;
	enableOnBoot = true;
        daemon.settings.features.cdi = true;  # ← REQUIRED for CDI GPU passthrough
        daemon.settings."log-driver" = "journald";  
      };

      # ── CDI Generator Race Condition Fix ──────────────────────────────
      systemd.services.nvidia-container-toolkit-cdi-generator = {
        after = [ "nvidia-persistenced.service" "systemd-modules-load.service" ];
        wants = [ "nvidia-persistenced.service" "systemd-modules-load.service" ];
        # Workaround for wait-for-nvidia-devices deadlock:
        serviceConfig.ExecStartPre = lib.mkForce [ ];
      };

      systemd.services.docker = {
        after = [ "nvidia-container-toolkit-cdi-generator.service" ];
        wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
        requires = [ "nvidia-container-toolkit-cdi-generator.service" ];  # stronger
      };

      # systemd.services.nvidia-container-toolkit-cdi-generator = {
      #   after = [ "nvidia-persistenced.service" ];
      #   wants = [ "nvidia-persistenced.service" ];
      # };
      # systemd.services.docker = {
      #   after = [ "nvidia-container-toolkit-cdi-generator.service" ];
      #   wants = [ "nvidia-container-toolkit-cdi-generator.service" ];
      # };

      # ── GPU Power Limits ──────────────────────────────────────────────
      systemd.services.nvidia-power-limits = {
        description = "Set power limit for all NVIDIA GPUs (Headless)";
        after = [ "nvidia-persistenced.service" ];
        requires = [ "nvidia-persistenced.service" ];  # ← Stronger dependency
        wantedBy = [ "multi-user.target" ];
        path = [ config.hardware.nvidia.package ];  # ← Correct reference for nvidia-smi
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          echo "Setting power limit for all NVIDIA cards: 230W."
          for gpu in $(nvidia-smi --query-gpu=index --format=csv,noheader); do
            nvidia-smi -i "$gpu" -pl 230
          done
        '';
      };

      # ── vLLM Docker Service ───────────────────────────────────────────
      systemd.services.club-3090 = {
        description = "vLLM Dual RTX 3090 (Qwen 3.6 27B)";
        after = [
          "network.target"
          "docker.service"
          "docker.socket"
          "nvidia-power-limits.service"
        ];
        requires = [
          "docker.service"
          "nvidia-power-limits.service"
        ];  # ← Stronger: fail if deps fail
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
          TimeoutStartSec = "15min";  # Uncomment for large model pulls
          StateDirectory = "vllm-dual-3090";
        };
      };
	#      # NVIDIA driver
	#      hardware.nvidia = {
	#        package = config.boot.kernelPackages.nvidiaPackages.stable;
	#        open = false;
	#        nvidiaSettings = false;
	# nvidiaPersistenced = true; 
	#        modesetting.enable = true;
	#      };
	#      hardware.graphics.enable32Bit = true;
	#      hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion = true;
	#
	#      virtualisation.docker = {
	#        enable = true;
	#        enableNvidia = true;
	#      };
	#
	#      systemd.services.nvidia-power-limits = {
	#        description = "Power limit for GPU 0 i 1 (Headless)";
	#        after = [ "nvidia-persistenced.service" ];
	#        wants = [ "nvidia-persistenced.service" ];
	#        wantedBy = [ "multi-user.target" ];
	#        path = [ config.boot.kernelPackages.nvidia-x11 ];
	#        serviceConfig = {
	#          Type = "oneshot";
	#          RemainAfterExit = true;
	#        };
	#        script = ''
	#          echo "Setting power limit for nvidia cards: 230W."
	#          nvidia-smi -i 0,1 -pl 230
	#        '';
	#      };
	#
	#      systemd.services.club-3090 = {
	#        description = "RTX 3090 Stack (Qwen Model)";
	#        after = [
	#          "network.target"
	#          "docker.service"
	#          "docker.socket"
	#          "nvidia-power-limits.service"
	#        ];
	#        wants = [ 
	#          "docker.service" 
	#          "nvidia-power-limits.service"
	#        ];
	#        wantedBy = [ "multi-user.target" ];
	#        path = with pkgs; [ 
	#          docker 
	#          curl 
	#        ];
	#        environment = {
	#          MODEL_DIR = "/home/m/models";
	#          CLUB3090_DEFAULT_QWEN3_6_27B = "vllm/dual";
	#          PORT = "8000";
	#        };
	#        preStart = ''
	#          echo "Prerun: pulling latest docker compose yaml..."
	#          YAML_URL='https://raw.githubusercontent.com/noonghunna/club-3090/refs/heads/master/models/qwen3.6-27b/vllm/compose/dual/autoround-int4/fp8-mtp.yml'
	#          curl -sSL "$YAML_URL" -o /var/lib/vllm-dual-3090/compose.yml
	#        '';
	#        script = ''
	#          echo "Starting vLLM docker compose..."
	#          exec docker compose -f /var/lib/vllm-dual-3090/compose.yml up --remove-orphans
	#        '';
	#        preStop = ''
	#          if [ -f /var/lib/vllm-dual-3090/compose.yml ]; then
	#            docker compose -f /var/lib/vllm-dual-3090/compose.yml down
	#          fi
	#        '';
	#        serviceConfig = {
	#          Type = "simple";
	#          Restart = "on-failure";
	#          RestartSec = "10s";
	#          # TimeoutStartSec = "10min";
	#          StateDirectory = "vllm-dual-3090"; 
	#        };
	#      };

      virtualisation.oci-containers.containers.dcgm-exporter = {
        image = "nvcr.io/nvidia/k8s/dcgm-exporter:4.4.1-4.6.0-ubuntu22.04";
        ports = [ "9400:9400" ];
        extraOptions = [ "--gpus=all" ];
      };
     
      systemd.services.gpu-aer-exporter = {
        description = "PCIe AER exporter";
        after = [ "systemd-journald.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = { Type = "simple"; Restart = "always"; User = "root"; };
        path = with pkgs; [ systemd gnugrep coreutils ];
        script = ''
          mkdir -p /var/lib/node_exporter
          COUNT=0
          journalctl -kf --grep="AER|PCIe Bus Error" -o cat | while read -r line; do
            COUNT=$((COUNT+1))
            cat > /var/lib/node_exporter/aer.prom <<EOF
pcie_aer_errors_total $COUNT
EOF
          done
        '';
      };

      systemd.services.gpu-crash-recorder = {
        description = "Record GPU diagnostics when NVIDIA Xid occurs";
        after = [ "sysinit.target" "systemd-journald.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = { Restart = "always"; RestartSec = "5"; User = "root"; };
        path = with pkgs; [ config.hardware.nvidia.package util-linux systemd pciutils coreutils gnugrep ];
        script = ''
          mkdir -p /var/log/gpu-crashes
          journalctl -kf --grep="NVRM: Xid" -o cat | while read -r line; do
            TS=$(date +%F-%H%M%S)
            DIR="/var/log/gpu-crashes/$TS"
            mkdir -p "$DIR"
            echo "$line" > "$DIR/crash-reason.txt"
            nvidia-smi -q > "$DIR/nvidia-smi-q.txt" 2>&1 || true
            nvidia-smi topo -m > "$DIR/topology.txt" 2>&1 || true
            dmesg > "$DIR/dmesg.txt" 2>&1 || true
            journalctl -b > "$DIR/journal.txt" 2>&1 || true
            lspci -vv > "$DIR/lspci.txt" 2>&1 || true
            sync
          done
        '';
      };

      systemd.services.gpu-health-exporter = {
        description = "GPU Health Exporter";
        after = [ "sysinit.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5";
          User = "root";
          ExecStart = pkgs.writeShellScript "gpu-health-exporter" ''
            mkdir -p /var/lib/node_exporter
            while true; do
              TMP=$(mktemp)
              echo "# HELP gpu_pcie_link_width PCIe width" >> "$TMP"
              echo "# TYPE gpu_pcie_link_width gauge" >> "$TMP"
              echo "# HELP gpu_pcie_link_speed PCIe speed" >> "$TMP"
              echo "# TYPE gpu_pcie_link_speed gauge" >> "$TMP"
              while read -r dev; do
                WIDTH=$(${pkgs.pciutils}/bin/lspci -vv -s "$dev" | grep LnkSta | sed -n 's/.*Width x\([0-9]*\).*/\1/p')
                SPEED=$(${pkgs.pciutils}/bin/lspci -vv -s "$dev" | grep LnkSta | sed -n 's/.*Speed \([0-9.]*\)GT.*/\1/p')
                echo "gpu_pcie_link_width{device=\"$dev\"} $WIDTH" >> "$TMP"
                echo "gpu_pcie_link_speed{device=\"$dev\"} $SPEED" >> "$TMP"
              done < <(${pkgs.pciutils}/bin/lvm_pv || ${pkgs.pciutils}/bin/lspci -D | grep -i nvidia | awk '{print $1}')
              mv "$TMP" /var/lib/node_exporter/gpu.prom
              sleep 30
            done
          '';
        };
      };

      systemd.services.nvidia-xid-exporter = {
        description = "NVIDIA Xid Exporter";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          ExecStart = pkgs.writeShellScript "nvidia-xid-exporter" ''
            mkdir -p /var/lib/node_exporter
            journalctl -kf -o cat | while read line; do
              echo "$line" | grep -q "Xid" || continue
              TS=$(date +%s)
              cat > /var/lib/node_exporter/nvidia_xid.prom <<EOF
nvidia_last_xid_timestamp $TS
EOF
            done
          '';
        };
        wantedBy = [ "multi-user.target" ];
      };

      # Alloy needs docker access for log collection
      users.users.alloy = {
        isSystemUser = true;
        group = "alloy";
        extraGroups = [ "docker" ];
      };
      users.groups.alloy = {};

      # PERSISTENT JOURNAL
      services.journald.extraConfig = ''
        Storage=persistent
        SystemMaxUse=20G
        RuntimeMaxUse=2G
        MaxRetentionSec=90day
      '';


      # Metrics: Prometheus Node Exporter + Server
      services.prometheus.exporters.node = {
        enable = true;
        port = 9100;
        enabledCollectors = [
          "systemd"
          "cpu"
          "meminfo"
          "diskstats"
          "filesystem"
          "netdev"
          "loadavg"
          "stat"
          "time"
          "thermal_zone"
          "hwmon"
        ];
        extraFlags = [
          "--collector.textfile.directory=/var/lib/node_exporter"
        ];
      };
      services.prometheus.exporters.smartctl = {
         enable = true;
         port = 9633;
      };
      services.smartd.enable = true;

      services.prometheus = {
        enable = true;
        port = 9090;
        retentionTime = "30d";
        scrapeConfigs = [
          {
            job_name = "baremetal_linux";
            static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
          }
          {
            job_name = "vllm";
            static_configs = [{ targets = [ "127.0.0.1:8000" ]; }];
          }
          {
            job_name = "dcgm";
            static_configs = [{
              targets = [ "127.0.0.1:9400" ];
            }];
          }
          {
            job_name = "prometheus";
            static_configs = [{
              targets = [ "127.0.0.1:9090" ];
            }];
          }
          {
            job_name = "smartctl";
            static_configs = [{
              targets = [ "127.0.0.1:9633" ];
            }];
          }
        ];
      };

      # Logs: Loki (custom config to avoid storage validation issues)
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
          labels = {
            host = "jimi"
            source = "journald"
          }
          forward_to = [loki.write.local.receiver]
        }
        loki.write "local" {
          endpoint {
            url = "http://127.0.0.1:3100/loki/api/v1/push"
          }
        }
      '';

      # Visualization: Grafana
      environment.etc."grafana/secret_key".text = "SW2YcwTIb9zpOOhoPsMm";

      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "0.0.0.0";
            http_port = 3001;
          };
          security.secret_key = "$__file{/etc/grafana/secret_key}";
        };

        provision = {
          enable = true;
          datasources.settings.datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://127.0.0.1:9090";
              isDefault = true;
            }
            {
              name = "Loki";
              type = "loki";
              url = "http://127.0.0.1:3100";
            }
          ];
        };
      };

      # CoolerControl user
      users.users.coolercontrol = {
        isSystemUser = true;
        group = "coolercontrol";
      };
      users.groups.coolercontrol = {};

      # Service user for s aspect
      users.users.s = {
        isSystemUser = true;
        group = "s";
      };
      users.groups.s = {};

      # Allow coolercontrol user to run ipmitool without password
      security.sudo.extraRules = [
        {
          users = [ "coolercontrol" ];
          commands = [
            {
              command = "${pkgs.ipmitool}/bin/ipmitool";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      # CoolerControl daemon
      systemd.services.coolercontrold = {
        description = "CoolerControl daemon";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "coolercontrol";
          ExecStart = "${pkgs.coolercontrol.coolercontrold}/bin/coolercontrold";
          Restart = "always";
          RestartSec = 5;
        };
      };

      # CoolerControl web UI
      systemd.services.coolercontrol-gui = {
        description = "CoolerControl web UI";
        after = [ "coolercontrold.service" ];
        wants = [ "coolercontrold.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.coolercontrol.coolercontrol-gui}/bin/coolercontrol-gui";
          Restart = "always";
          RestartSec = 5;
        };
      };

      # Install coolercontrol plugins
      system.activationScripts.install-coolercontrol-plugins = ''
        echo "installing coolercontrol plugins..."

        # Corsair PSU plugin
        mkdir -p /etc/coolercontrol/plugins/corsair-psu/ui
        cp ${inputs.corsair-psu.packages.${pkgs.system}.default}/bin/corsair-psu /etc/coolercontrol/plugins/corsair-psu/
        cp ${inputs.corsair-psu.packages.${pkgs.system}.default}/plugin-files/manifest.toml /etc/coolercontrol/plugins/corsair-psu/
        if [ -f ${inputs.corsair-psu.packages.${pkgs.system}.default}/plugin-files/ui/index.html ]; then
          cp ${inputs.corsair-psu.packages.${pkgs.system}.default}/plugin-files/ui/index.html /etc/coolercontrol/plugins/corsair-psu/ui/
        fi

        # IPMI plugin (custom-device)
        mkdir -p /etc/coolercontrol/plugins/custom-device
        cp ${inputs.ipmi-plugin.packages.${pkgs.system}.default}/bin/custom-device /etc/coolercontrol/plugins/custom-device/
        cp ${inputs.ipmi-plugin.packages.${pkgs.system}.default}/plugin-files/manifest.toml /etc/coolercontrol/plugins/custom-device/
        cp ${inputs.ipmi-plugin.packages.${pkgs.system}.default}/plugin-files/config.json /etc/coolercontrol/plugins/custom-device/

        # Ensure coolercontrol user owns all plugin files
        chown -R coolercontrol:coolercontrol /etc/coolercontrol
      '';

      # System packages
      environment.systemPackages = [
        pkgs.yazi
        pkgs.ripgrep
        pkgs.fd
        pkgs.btop
        pkgs.ipmitool
        pkgs.git
        pkgs.curl
        pkgs.wget
        pkgs.python3
        pkgs.yq
        pkgs.coolercontrol.coolercontrol-gui
        pkgs.coolercontrol.coolercontrold
      ];


      # Allow passwordless sudo for m
      security.sudo.wheelNeedsPassword = false;

      system.stateVersion = "26.05";
    };

    homeManager = { pkgs, ... }: {
      home.packages = [
        pkgs.yazi
        pkgs.ripgrep
        pkgs.fd
        pkgs.btop
        pkgs.coolercontrol.coolercontrol-gui
        pkgs.coolercontrol.coolercontrold
      ];
    };
  };
}
