{ config, pkgs, lib, inputs, ... }:

let
  arrUser = "arr";
  arrGroup = "arr";
in
{
  imports = [
    ./hardware/rpi4.nix
    inputs.rustledger.nixosModules.default
    inputs.rustfava.nixosModules.default
  ];

  # Hostname
  networking.hostName = "rpi4-server";

  # Boot configuration
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Time zone
  time.timeZone = "Europe/Warsaw";

  # Internationalisation
  i18n.defaultLocale = "en_US.UTF-8";

  # Nix settings
  nix = {
    package = pkgs.nixVersions.latest;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # User account
  users.users.m = {
    isNormalUser = true;
    home = "/home/m";
    extraGroups = [ "wheel" "networkmanager" "docker" "finance" "audio" "arr" "syncthing" ];
    openssh.authorizedKeys.keyFiles = [ ./generated/rpi-host-authorized-keys ];
  };

  # Password for user (set via secret)
  users.users.m.hashedPasswordFile = config.sops.secrets."user/hashed-password".path;

  # Sudo configuration
  security.sudo.wheelNeedsPassword = true;

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = false;
    authKeyFile = config.sops.secrets."tailscale/auth-key".path;
    extraUpFlags = [
      "--advertise-exit-node"
      "--ssh"
    ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "m" ];
    };
  };

  # ============================================================
  # NAS CONFIGURATION (MergerFS + SnapRAID + Samba + NFS)
  # ============================================================
  
  # Install required packages
  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
    snapraid
    smartmontools
    hd-idle
  ];

  # MergerFS pool - combines all data drives
  # Drives: 250GB + 1TB + 500GB = ~1.75TB usable (1TB used for parity)
  fileSystems."/data" = {
    device = "/mnt/disk1:/mnt/disk2:/mnt/disk3";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"
      "moveonenospc=true"
      "minfreespace=10G"
      "fsname=mergerfs-data"
    ];
    depends = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" ];
  };

  # Create data directories
  systemd.tmpfiles.rules = [
    "d /data/media 0755 root root -"
    "d /data/media/movies 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/tv 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/music 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/downloads 0775 ${arrUser} ${arrGroup} -"
    "d /data/audiobooks 0755 root root -"
    "d /data/backups 0755 root root -"
    "d /data/backups/finance 0750 finance finance -"
    "d /data/backups/timemachine 0755 root root -"
  ];

  # SnapRAID configuration
  environment.etc."snapraid.conf".text = ''
    parity /mnt/parity1/snapraid.parity
    
    content /mnt/disk1/.snapraid.content
    content /mnt/disk2/.snapraid.content
    content /mnt/disk3/.snapraid.content
    content /var/lib/snapraid/.snapraid.content
    
    disk d1 /mnt/disk1/
    disk d2 /mnt/disk2/
    disk d3 /mnt/disk3/
    
    exclude *.tmp
    exclude /downloads/
    exclude .snapraid.content
    exclude .mergerfs
    
    autosave 1000
    blocksize 256
    hashsize 16
  '';

  # SnapRAID sync service (daily)
  systemd.services.snapraid-sync = {
    description = "SnapRAID Synchronization";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.snapraid}/bin/snapraid sync";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.snapraid-sync = {
    description = "Run SnapRAID sync daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  # SnapRAID scrub service (weekly)
  systemd.services.snapraid-scrub = {
    description = "SnapRAID Scrub";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.snapraid}/bin/snapraid scrub -p 10";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.snapraid-scrub = {
    description = "Run SnapRAID scrub weekly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };
  };

  # SMART monitoring
  services.smartd = {
    enable = true;
  };

  # Spin down idle drives
  services.hd-idle = {
    enable = true;
    settings = {
      "*" = { spindown = 600; };
    };
  };

  # Samba configuration
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "RPI4 NAS";
        "security" = "user";
        "map to guest" = "bad user";
        "guest account" = "nobody";
        "fruit:encoding" = "native";
        "fruit:metadata" = "stream";
        "fruit:zero_file_id" = "yes";
        "fruit:nfs_aces" = "no";
        "vfs objects" = "catia fruit streams_xattr";
      };
      
      media = {
        path = "/data/media";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "valid users" = "m";
      };
      
      audiobooks = {
        path = "/data/audiobooks";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "m";
      };
      
      backups = {
        path = "/data/backups";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "m";
      };
      
      timemachine = {
        path = "/data/backups/timemachine";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "m";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "500G";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # NFS exports
  services.nfs.server = {
    enable = true;
    exports = ''
      /data 192.168.0.0/16(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # ============================================================
  # ARR STACK (LAN-Only)
  # ============================================================
  
  # Create arr user and group
  users.users.${arrUser} = {
    isSystemUser = true;
    group = arrGroup;
    home = "/var/lib/arr";
    createHome = true;
  };
  
  users.groups.${arrGroup} = {};

  # Prowlarr - Indexer manager
  services.prowlarr = {
    enable = true;
    openFirewall = false;
  };

  # Radarr - Movies
  services.radarr = {
    enable = true;
    openFirewall = false;
    user = arrUser;
    group = arrGroup;
    dataDir = "/var/lib/arr/radarr";
  };

  # Sonarr - TV
  services.sonarr = {
    enable = true;
    openFirewall = false;
    user = arrUser;
    group = arrGroup;
    dataDir = "/var/lib/arr/sonarr";
  };

  # Lidarr - Music
  services.lidarr = {
    enable = true;
    openFirewall = false;
    user = arrUser;
    group = arrGroup;
    dataDir = "/var/lib/arr/lidarr";
  };

  # Transmission - Torrent client
  services.transmission = {
    enable = true;
    openFirewall = false;
    openRPCPort = false;
    settings = {
      download-dir = "/data/media/downloads";
      incomplete-dir = "/data/media/downloads/.incomplete";
      incomplete-dir-enabled = true;
      rpc-bind-address = "0.0.0.0";
      rpc-port = 9091;
      rpc-authentication-required = true;
      rpc-username = "m";
      ratio-limit = 0;
      ratio-limit-enabled = true;
      speed-limit-down = 10000;
      speed-limit-down-enabled = true;
      speed-limit-up = 1000;
      speed-limit-up-enabled = true;
      utp-enabled = true;
      dht-enabled = true;
      pex-enabled = true;
      lpd-enabled = true;
      message-level = 1;
    };
  };

  # Jellyfin - Media server
  services.jellyfin = {
    enable = true;
    openFirewall = false;
    user = arrUser;
    group = arrGroup;
    dataDir = "/var/lib/arr/jellyfin";
    configDir = "/var/lib/arr/jellyfin/config";
    logDir = "/var/lib/arr/jellyfin/log";
  };

  # ============================================================
  # FINANCE STACK (VPN-Only)
  # ============================================================
  
  # Create finance user
  users.users.finance = {
    isSystemUser = true;
    group = "finance";
    home = "/var/lib/finance";
    createHome = true;
  };
  
  users.groups.finance = {};

  # rustledger and rustfava from flakes
  services.rustledger = {
    enable = true;
    user = "finance";
    group = "finance";
    dataDir = "/var/lib/finance/data";
  };

  services.rustfava = {
    enable = true;
    user = "finance";
    group = "finance";
    port = 5000;
    host = "0.0.0.0";
    dataDir = "/var/lib/finance/data";
  };

  # Automatic backup of finance data to NAS
  systemd.services.finance-backup = {
    description = "Backup finance data to NAS";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "finance-backup" ''
        set -e
        SOURCE="/var/lib/finance/data"
        DEST="/data/backups/finance"
        
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$DEST"
        
        ${pkgs.rsync}/bin/rsync -av --delete "$SOURCE/" "$DEST/current/"
        
        cp -al "$DEST/current" "$DEST/snapshot_$TIMESTAMP"
        
        cd "$DEST" && ls -t -d snapshot_* 2>/dev/null | tail -n +31 | xargs -r rm -rf
        
        echo "Backup completed: $TIMESTAMP"
      '';
      User = "finance";
      Group = "finance";
    };
  };

  systemd.timers.finance-backup = {
    description = "Run finance backup hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # ============================================================
  # AUDIO STREAMING (VPN-Only)
  # ============================================================
  
  # Create audio user
  users.users.audio = {
    isSystemUser = true;
    group = "audio";
    home = "/var/lib/audio";
    createHome = true;
  };
  
  users.groups.audio = {};

  systemd.tmpfiles.rules = [
    "d /var/lib/audio/jellyfin 0755 audio audio -"
  ];

  # Separate Jellyfin instance for audio
  systemd.services.jellyfin-audio = {
    description = "Jellyfin Media Server (Audio Instance)";
    after = [ "network.target" ];
    wants = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "audio";
      Group = "audio";
      WorkingDirectory = "/var/lib/audio/jellyfin";
      ExecStart = "${pkgs.jellyfin}/bin/jellyfin --datadir /var/lib/audio/jellyfin --cachedir /var/lib/audio/jellyfin/cache";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutSec = 15;
      
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/audio/jellyfin" "/data/media/music" "/data/audiobooks" ];
      
      MemoryMax = "512M";
      CPUQuota = "50%";
    };

    environment = {
      "JELLYFIN_PublishedServerUrl" = "http://rpi4-audio:8097";
    };
  };

  # ============================================================
  # SYNCTHING BACKUP (VPN-Only)
  # ============================================================
  
  services.syncthing = {
    enable = true;
    openDefaultPorts = false;
    
    user = "syncthing";
    group = "syncthing";
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/config";
    
    overrideDevices = true;
    overrideFolders = true;
    
    settings = {
      devices = {};
      
      folders = {
        "finance-backup" = {
          path = "/data/backups/finance/current";
          id = "finance-backup";
          label = "Finance Backup";
          type = "sendonly";
          devices = [];
          versioning = {
            type = "simple";
            params.keep = "10";
          };
        };
      };
      
      gui = {
        enabled = true;
        address = "127.0.0.1:8384";
        user = "m";
      };
      
      options = {
        globalAnnounceEnabled = false;
        localAnnounceEnabled = true;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
    };
  };

  users.users.syncthing = {
    isSystemUser = true;
    group = "syncthing";
    home = "/var/lib/syncthing";
    createHome = true;
  };
  
  users.groups.syncthing = {};

  systemd.services.syncthing.serviceConfig = {
    SupplementaryGroups = [ "finance" ];
    ReadWritePaths = [ "/var/lib/syncthing" "/data/backups/finance" ];
  };

  # ============================================================
  # FIREWALL CONFIGURATION
  # ============================================================
  
  networking.firewall = {
    enable = true;
    default = "drop";
    allowPing = true;
    
    # SSH always allowed
    allowedTCPPorts = [ 22 ];
    
    # NFS ports
    allowedTCPPorts = [ 111 2049 4000 4001 4002 ];
    allowedUDPPorts = [ 111 2049 4000 4001 4002 ];
    
    # Tailscale interface - VPN services
    interfaces.tailscale0 = {
      allowedTCPPorts = [
        22
        5000    # rustfava
        8097    # Jellyfin audio
        22000   # Syncthing
      ];
      allowedUDPPorts = [
        config.services.tailscale.port
        22000   # Syncthing QUIC
        21027   # Syncthing local discovery
      ];
    };
    
    # LAN interface - NAS and Arr stack
    interfaces.eth0 = {
      allowedTCPPorts = [
        80      # nginx
        443     # nginx
        7878    # Radarr
        8989    # Sonarr
        8686    # Lidarr
        9696    # Prowlarr
        9091    # Transmission
        8096    # Jellyfin
      ];
    };
    
    # Block VPN services from LAN
    extraCommands = ''
      iptables -A INPUT -i eth0 -p tcp --dport 5000 -j DROP
      iptables -A INPUT -i eth0 -p tcp --dport 8097 -j DROP
      iptables -A INPUT -i eth0 -p tcp --dport 22000 -j DROP
      iptables -A INPUT -i eth0 -p udp --dport 22000 -j DROP
      iptables -A INPUT -i eth0 -p udp --dport 21027 -j DROP
      
      # Block arr stack from VPN
      iptables -A INPUT -i tailscale0 -p tcp --dport 7878 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8989 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8686 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 9696 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 9091 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8096 -j DROP
      
      # Block Syncthing GUI from all external
      iptables -A INPUT -i eth0 -p tcp --dport 8384 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8384 -j DROP
    '';
  };

  # ============================================================
  # SECRETS MANAGEMENT
  # ============================================================
  
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.age.generateKey = true;
  sops.age.sshKeyPaths = [];
  sops.gnupg.sshKeyPaths = [];
  
  sops.secrets."tailscale/auth-key" = {
    collect.rbw.id = "tailscale-auth-key";
  };
  sops.secrets."user/hashed-password" = {
    collect.rbw.id = "nixos-hashed-password";
    neededForUsers = true;
  };

  # ============================================================
  # ESSENTIAL PACKAGES
  # ============================================================
  
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    iotop
    tmux
    rsync
    smartmontools
    lm_sensors
    pciutils
    usbutils
  ];

  # Enable firmware
  hardware.enableRedistributableFirmware = true;

  # System state version
  system.stateVersion = "25.11";
}
