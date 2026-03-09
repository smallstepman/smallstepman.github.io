{ config, pkgs, lib, currentSystem, currentSystemName, inputs, ... }:

{
  imports = [
    ./hardware/thinkpad-x1-extreme-gen1.nix
    ./hardware/disko-thinkpad-x1-extreme.nix
  ];

  sops.hostPubKey = lib.removeSuffix "\n" (builtins.readFile ./generated/x1e-age-pubkey);

  # Hostname
  networking.hostName = "x1-homelab";
  networking.hosts."127.0.0.1" = [ "x1-homelab" "localhost" ];

  # Kernel - use latest for better hardware support
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Nix configuration
  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
  };

  nixpkgs.config.permittedInsecurePackages = [
    # Needed for k2pdfopt 2.53.
    "mupdf-1.17.0"
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Timezone
  time.timeZone = "Europe/Warsaw";

  # Networking
  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;      # Ethernet
  networking.interfaces.wlp0s20f3.useDHCP = true; # WiFi (Intel)

  # Enable NetworkManager
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved = {
    enable = true;
    fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
  };

  # Require password for sudo but cache it for 10 minutes.
  security.sudo.wheelNeedsPassword = true;
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=10
  '';

  # Users
  users.mutableUsers = false;

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: Automatic System Updates
  # ═════════════════════════════════════════════════════════════════════════════
  # Automatically updates NixOS daily at 4 AM with a randomized delay.
  # The system will download and apply updates automatically.
  # Rollback is available via boot menu if something breaks.
  # 
  # TO DISABLE: Comment out or set enable = false;
  # ─────────────────────────────────────────────────────────────────────────────
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [ "--update-input" "nixpkgs" "-L" ];
    dates = "04:00";  # 4 AM daily
    randomizedDelaySec = "45min";
    allowReboot = false;  # Don't auto-reboot, just apply
  };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: Ollama - Local LLM Inference Server
  # ═════════════════════════════════════════════════════════════════════════════
  # Runs large language models locally on your NVIDIA GTX 1050 GPU.
  # Accessible via Tailscale from anywhere.
  # Compatible with: Continue.dev, Claude Code, OpenAI-compatible APIs.
  # 
  # USAGE:
  #   ollama run llama3.2          # Run a model
  #   ollama list                  # See installed models
  #   curl http://x1-homelab:11434/api/generate -d '{"model":"llama3.2","prompt":"hello"}'
  #
  # TO DISABLE: Comment out or set enable = false;
  # NOTE: Requires at least 4GB VRAM for most models
  # ─────────────────────────────────────────────────────────────────────────────
  services.ollama = {
    enable = true;
    acceleration = "cuda";  # Use NVIDIA GPU (set to "rocm" for AMD, remove for CPU-only)
    host = "0.0.0.0";       # Listen on all interfaces (Tailscale will secure this)
    port = 11434;
    # Models are stored in /var/lib/ollama
  };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: Prometheus + Grafana - Cluster Monitoring & Dashboards
  # ═════════════════════════════════════════════════════════════════════════════
  # Collects metrics from k3s, hardware sensors, and NVIDIA GPU.
  # Grafana provides web dashboards accessible via Tailscale.
  # 
  # ACCESS:
  #   Grafana UI: http://x1-homelab:3000 (default login: admin/admin)
  #   Prometheus: http://x1-homelab:9090
  #
  # TO DISABLE: Comment out the entire section below
  # ─────────────────────────────────────────────────────────────────────────────
  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "30d";  # Keep 30 days of metrics
    
    # Scrape k3s components
    scrapeConfigs = [
      {
        job_name = "k3s-api";
        static_configs = [{ targets = [ "localhost:6443" ]; }];
        tls_config = {
          insecure_skip_verify = true;
        };
      }
      {
        job_name = "k3s-cadvisor";
        static_configs = [{ targets = [ "localhost:10250" ]; }];
      }
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:9100" ]; }];
      }
      {
        job_name = "nvidia-gpu";
        static_configs = [{ targets = [ "localhost:9400" ]; }];
      }
    ];
    
    # Enable node exporter for hardware metrics
    exporters = {
      node = {
        enable = true;
        port = 9100;
        enabledCollectors = [ "systemd" "processes" "interrupts" ];
      };
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";  # Accessible via Tailscale
        http_port = 3000;
      };
      security = {
        admin_user = "admin";
        # Set admin_password in secrets.yaml and reference here if desired
        # For now using default "admin" - change on first login!
      };
    };
    
    # Auto-provision Prometheus datasource
    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://localhost:9090";
        isDefault = true;
      }
    ];
  };

  # NVIDIA Data Center GPU Manager (DCGM) exporter for GPU metrics
  # Provides detailed GPU utilization, temperature, memory usage
  # TO DISABLE: Remove this systemd service
  systemd.services.nvidia-dcgm-exporter = {
    description = "NVIDIA DCGM Exporter";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "nvidia-persistenced.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.dcgm}/bin/dcgm-exporter";
      Restart = "always";
    };
  };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: Local Container Registry Cache
  # ═════════════════════════════════════════════════════════════════════════════
  # Caches pulled Docker images locally. Speeds up redeploys and saves bandwidth.
  # Acts as a pull-through cache to Docker Hub.
  #
  # USAGE: Set registry mirror in /etc/docker/daemon.json:
  #   { "registry-mirrors": ["http://localhost:5000"] }
  #
  # TO DISABLE: Comment out or set enable = false;
  # ─────────────────────────────────────────────────────────────────────────────
  services.dockerRegistry = {
    enable = true;
    listenAddress = "127.0.0.1";  # Local only for security
    port = 5000;
    extraConfig = {
      proxy = {
        remoteurl = "https://registry-1.docker.io";
        username = "";
        password = "";
      };
    };
  };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: BorgBackup - Encrypted Deduplicated Backups
  # ═════════════════════════════════════════════════════════════════════════════
  # Backs up k3s state and important data weekly.
  # Uses compression (zstd) and encryption.
  #
  # CONFIGURE: Update 'repo' to your backup destination:
  #   - Local: /mnt/backup/homelab
  #   - Remote: ssh://user@backup-server/~/homelab
  #   - Cloud: rclone remote (configure separately)
  #
  # TO DISABLE: Comment out the entire section
  # NOTE: You MUST configure a backup destination first!
  # ─────────────────────────────────────────────────────────────────────────────
  # services.borgbackup.jobs.homelab = {
  #   paths = [ 
  #     "/var/lib/rancher/k3s/server"   # k3s server state
  #     "/var/lib/docker"                # Docker data (optional, can be large)
  #     "/var/lib/ollama"                # Downloaded LLM models
  #     "/etc/nixos"                     # NixOS configuration
  #   ];
  #   repo = "/mnt/backup/homelab";  # <-- CHANGE THIS to your backup location
  #   encryption.mode = "repokey-blake2";
  #   encryption.passCommand = "cat ${config.sops.secrets."borg/repokey".path}";
  #   compression = "zstd,15";
  #   startAt = "weekly";
  #   prune.keep = {
  #     weekly = 4;
  #     monthly = 6;
  #   };
  # };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: Smart Power Management
  # ═════════════════════════════════════════════════════════════════════════════
  # Optimizes CPU frequency scaling for better battery life and performance.
  # Automatically switches between power-saving and performance modes.
  #
  # TO DISABLE: Comment out
  # ─────────────────────────────────────────────────────────────────────────────
  services.auto-cpufreq.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    # ═══════════════════════════════════════════════════════════════════════════
    # GitOps Tools
    # ═══════════════════════════════════════════════════════════════════════════
    fluxcd           # Flux CLI for GitOps (declarative k8s deployments)
    # Usage: flux bootstrap github --owner=<user> --repo=<repo> --path=clusters/x1-homelab
    # After bootstrap: Push manifests to Git, Flux auto-applies them

    # ═══════════════════════════════════════════════════════════════════════════
    # Core System Tools
    # ═══════════════════════════════════════════════════════════════════════════
    git
    htop
    iotop
    lm_sensors       # Hardware temperature/fan monitoring
    pciutils         # lspci - PCI device info
    usbutils         # lsusb - USB device info
    ethtool          # Network interface settings

    # ═══════════════════════════════════════════════════════════════════════════
    # GPU Tools
    # ═══════════════════════════════════════════════════════════════════════════
    nvtop            # GPU monitoring (like htop for NVIDIA)
    # nvidia-offload is provided by the NVIDIA module when prime.offload.enable = true

    # ═══════════════════════════════════════════════════════════════════════════
    # Kubernetes Tools
    # ═══════════════════════════════════════════════════════════════════════════
    kubectl          # Control k3s cluster
    kubernetes-helm  # Package manager for k8s
    k9s              # Terminal UI for k8s (highly recommended!)
    stern            # Multi-pod log viewer (better than kubectl logs)

    # ═══════════════════════════════════════════════════════════════════════════
    # LLM / AI Tools
    # ═══════════════════════════════════════════════════════════════════════════
    ollama           # CLI for managing local LLMs
    # Usage: ollama run llama3.2, ollama list, ollama pull mistral

    # ═══════════════════════════════════════════════════════════════════════════
    # Backup Tools
    # ═══════════════════════════════════════════════════════════════════════════
    borgbackup       # Deduplicated encrypted backups
    # Usage: borg create, borg list, borg extract

    # ═══════════════════════════════════════════════════════════════════════════
    # Desktop Environment
    # ═══════════════════════════════════════════════════════════════════════════
    wl-clipboard       # Wayland clipboard utilities
    wezterm            # GPU-accelerated terminal
  ];

  # Fonts
  fonts = {
    fontDir.enable = true;
    packages = [
      pkgs.fira-code
      pkgs.jetbrains-mono
    ];
  };

  # Enable niri (scrollable-tiling Wayland compositor)
  # Using Intel GPU for display
  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };

  # Enable Noctalia shell service for Wayland sessions
  services.noctalia-shell.enable = true;

  # Enable mango (Wayland compositor) - configured via home-manager
  programs.mango.enable = true;

  # greetd with tuigreet
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # Keep xserver for XWayland support
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";

  # Modifier remap via keyd
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        leftmeta = "leftcontrol";
        leftcontrol = "leftalt";
        leftalt = "leftmeta";
        rightalt = "rightmeta";
        rightcontrol = "rightalt";
        rightmeta = "rightcontrol";
      };
    };
  };

  # Intel GPU for display (modesetting driver)
  # NVIDIA for compute only
  services.xserver.videoDrivers = [ 
    "modesetting"  # Intel iGPU for display
    "nvidia"       # NVIDIA for compute
  ];

  # NVIDIA GPU configuration - compute only
  hardware.graphics.enable = true;
  
  hardware.nvidia = {
    # GTX 1050 uses legacy 470 driver
    package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
    
    # Enable modesetting for Wayland
    modesetting.enable = true;
    
    # Enable NVIDIA persistenced for compute workloads
    nvidiaPersistenced = true;
    
    # Power management
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    
    # Use proprietary drivers (GTX 10-series doesn't support open kernel modules)
    open = false;

    # PRIME configuration: Intel renders display, NVIDIA available for compute
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      # Intel UHD Graphics 630
      intelBusId = "PCI:0@0:2:0";
      # NVIDIA GTX 1050 Ti Max-Q
      nvidiaBusId = "PCI:1@0:0:0";
    };
  };

  # Noctalia prerequisites
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # Internationalization
  i18n = {
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5.addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-gtk
        fcitx5-hangul
        fcitx5-mozc
      ];
      fcitx5.waylandFrontend = true;
    };
  };

  # Tailscale
  services.tailscale.enable = true;
  services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth-key".path;

  # OpenSSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      PermitRootLogin = "no";
      AllowUsers = [ "m" ];
    };
  };

  # k3s configuration
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik"
      "--disable=servicelb"
      "--kubelet-arg=eviction-hard=memory.available<500Mi,nodefs.available<10%"
    ];
  };

  # Containerd configuration for NVIDIA runtime
  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia = {
        privileged_without_host_devices = false;
        runtime_engine = "";
        runtime_root = "";
        runtime_type = "io.containerd.runc.v2";
        options = {
          BinaryName = "${pkgs.nvidia-docker}/bin/nvidia-container-runtime";
        };
      };
    };
  };

  # Docker with NVIDIA support
  virtualisation.docker = {
    enable = true;
    enableNvidia = true;
  };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: GitOps with Flux CD - Declarative Git-Based Deployments
  # ═════════════════════════════════════════════════════════════════════════════
  # Flux automatically syncs your Git repository with the k3s cluster.
  # When you push changes to Git, Flux applies them to the cluster automatically.
  # No manual kubectl apply needed!
  #
  # SETUP:
  #   1. Create a Git repo for your Kubernetes manifests (e.g., homelab-gitops)
  #   2. Bootstrap Flux: flux bootstrap github --owner=YOURUSER --repository=homelab-gitops --path=clusters/x1-homelab
  #   3. Add manifests to the repo and they'll auto-deploy
  #
  # BENEFITS:
  #   - Git as single source of truth
  #   - Drift detection (alerts if cluster diverges from Git)
  #   - Automated updates (can auto-apply new container images)
  #   - Disaster recovery (rebuild cluster from Git)
  #
  # TO DISABLE: Comment out the entire section
  # ALTERNATIVE: You can also use ArgoCD (comment this out and use ArgoCD instead)
  # ─────────────────────────────────────────────────────────────────────────────
  services.fluxcd = {
    enable = true;
    # The Flux CLI is installed via system packages
    # Bootstrap must be run manually after k3s is ready:
    #   flux bootstrap github --owner=<you> --repo=<repo> --path=clusters/x1-homelab
  };

  # ═════════════════════════════════════════════════════════════════════════════
  # OPTIONAL: Kubernetes Dashboard - Web UI for Cluster Management
  # ═════════════════════════════════════════════════════════════════════════════
  # Provides a web-based UI to view and manage k3s resources.
  # More user-friendly than kubectl for exploration.
  #
  # ACCESS:
  #   kubectl proxy &
  #   Open: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
  #   Login: Use token from 'kubectl -n kubernetes-dashboard create token admin-user'
  #
  # TO DISABLE: Comment out
  # ─────────────────────────────────────────────────────────────────────────────
  # services.kubernetes.dashboard = {
  #   enable = true;
  #   # Additional RBAC setup required - see docs
  # };

  # Secrets management
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.generateKey = true;
  sops.age.sshKeyPaths = [];
  sops.gnupg.sshKeyPaths = [];
  sops.secrets."tailscale/auth-key" = {
    collect.rbw.id = "tailscale-auth-key";
  };
  sops.secrets."rbw/email" = {
    collect.rbw.id = "bitwarden-email";
    owner = "m";
    mode = "0400";
  };
  sops.secrets."uniclip/password" = {
    collect.rbw.id = "uniclip-password";
    owner = "m";
    mode = "0400";
  };
  sops.secrets."user/hashed-password" = {
    collect.rbw.id = "nixos-hashed-password";
    neededForUsers = true;
  };

  # Firewall
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" "eno1" "wlp0s20f3" ];
    allowedTCPPorts = [ 
      22     # SSH
      6443   # k3s API server
    ];
    allowedUDPPorts = [ 
      config.services.tailscale.port 
    ];
  };

  # Escape hatches
  services.flatpak.enable = true;
  services.snap.enable = true;

  # State version
  system.stateVersion = "25.11";
}
