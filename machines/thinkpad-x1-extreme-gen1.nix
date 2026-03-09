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

  # System packages
  environment.systemPackages = with pkgs; [
    git
    htop
    iotop
    lm_sensors
    pciutils
    usbutils
    kubectl
    kubernetes-helm
    k9s
    ethtool
    nvtop              # GPU monitoring
    wl-clipboard       # Wayland clipboard
    wezterm
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
