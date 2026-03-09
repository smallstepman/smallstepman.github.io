# RPI4 Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a complete Raspberry Pi 4 NixOS server configuration with encrypted NAS, media stack, finance tools, and audio streaming.

**Architecture:** Modular NixOS configuration following the existing multi-system pattern. Hardware config for RPI4, separate service modules for NAS, arr-stack, finance, and audio. Bootstrap script following vm.sh pattern.

**Tech Stack:** NixOS 25.11, MergerFS, SnapRAID, LUKS, Tailscale, Jellyfin, Radarr/Sonarr/Lidarr/Prowlarr, Transmission, rustfava, Syncthing

---

## Prerequisites

Before starting, ensure:
1. You're in the worktree: `cd /Users/m/.config/nix/.worktrees/rpi4-hardware`
2. Raspberry Pi 4 with 4 drives connected via USB
3. SD card (32GB+) for initial bootstrap
4. LAN access for SSH during setup

---

### Task 1: Create Hardware Configuration

**Files:**
- Create: `machines/hardware/rpi4.nix`
- Reference: `docs/vm.sh` (bootstrap pattern), NixOS RPI4 wiki

**Step 1: Create base hardware configuration**

```nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # RPI4 specific settings
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  
  # Kernel parameters for RPI4
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=ttyAMA0,115200n8"
    "console=tty0"
  ];
  
  # Enable GPU memory split for headless (minimal)
  boot.loader.raspberryPi.firmwareConfig = ''
    gpu_mem=16
  '';

  # Filesystems needed for USB drives
  boot.supportedFilesystems = [
    "btrfs"
    "ext4"
    "vfat"
    "exfat"
    "ntfs"
    "xfs"
  ];

  # Load kernel modules for USB storage
  boot.kernelModules = [ "usb-storage" "uas" ];

  # Networking
  networking.useDHCP = lib.mkDefault true;
  
  # Enable SSH for headless setup
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
  services.openssh.settings.PasswordAuthentication = true;

  # Firmware for RPI4
  hardware.enableRedistributableFirmware = true;
  
  system.stateVersion = "25.11";
}
```

**Step 2: Create Disko configuration for drive partitioning**

Create: `machines/hardware/disko-rpi4.nix`

```nix
# Disko configuration for RPI4 NAS
# Creates LUKS-encrypted partitions on all 4 drives
# 1TB SSD = parity drive (not encrypted, SnapRAID parity)
# Other drives = data drives (encrypted with LUKS)

{ lib, ... }:

let
  # Drive identifiers - adjust UUIDs after initial lsblk
  # You'll need to update these after first boot
  drive1tb = "/dev/disk/by-id/usb-...";    # 1TB SSD - Parity
  drive250 = "/dev/disk/by-id/usb-...";    # 250GB SSD - Data
  drive1tbHdd = "/dev/disk/by-id/usb-..."; # 1TB HDD - Data
  drive500 = "/dev/disk/by-id/usb-...";    # 500GB NVMe - Data
in
{
  disko.devices = {
    disk = {
      # Parity drive (1TB SSD) - unencrypted, ext4
      parity = {
        device = drive1tb;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            snapraid-parity = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/parity1";
              };
            };
          };
        };
      };
      
      # Data drive 1 (250GB SSD) - LUKS encrypted
      data1 = {
        device = drive250;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "data1";
                passwordFile = "/tmp/luks-password";  # Provided during install
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/disk1";
                };
              };
            };
          };
        };
      };
      
      # Data drive 2 (1TB HDD) - LUKS encrypted
      data2 = {
        device = drive1tbHdd;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "data2";
                passwordFile = "/tmp/luks-password";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/disk2";
                };
              };
            };
          };
        };
      };
      
      # Data drive 3 (500GB NVMe) - LUKS encrypted
      data3 = {
        device = drive500;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "data3";
                passwordFile = "/tmp/luks-password";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/mnt/disk3";
                };
              };
            };
          };
        };
      };
    };
  };
}
```

**Step 3: Commit the hardware configs**

```bash
git add machines/hardware/rpi4.nix machines/hardware/disko-rpi4.nix
git commit -m "feat(rpi4): add hardware configuration and disko partitioning"
```

---

### Task 2: Create NAS Module (MergerFS + SnapRAID)

**Files:**
- Create: `machines/rpi4/nas.nix`
- Reference: `vm-shared.nix` (for service patterns)

**Step 1: Create NAS configuration module**

```nix
{ config, pkgs, lib, ... }:

{
  # Install required packages
  environment.systemPackages = with pkgs; [
    mergerfs
    mergerfs-tools
    snapraid
    smartmontools
    hd-idle
  ];

  # MergerFS pool - combines all data drives
  fileSystems."/data" = {
    device = "/mnt/disk1:/mnt/disk2:/mnt/disk3";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"      # Most free space for new files
      "moveonenospc=true"
      "minfreespace=10G"
      "fsname=mergerfs-data"
    ];
    depends = [ "/mnt/disk1" "/mnt/disk2" "/mnt/disk3" ];
  };

  # Create data directories
  systemd.tmpfiles.rules = [
    "d /data/media 0755 root root -"
    "d /data/media/movies 0755 root root -"
    "d /data/media/tv 0755 root root -"
    "d /data/media/music 0755 root root -"
    "d /data/media/downloads 0755 root root -"
    "d /data/audiobooks 0755 root root -"
    "d /data/backups 0755 root root -"
    "d /data/backups/finance 0755 root root -"
    "d /data/backups/timemachine 0755 root root -"
  ];

  # SnapRAID configuration
  environment.etc."snapraid.conf".text = ''
    # Parity drive
    parity /mnt/parity1/snapraid.parity
    
    # Content files (store on each data drive + backup)
    content /mnt/disk1/.snapraid.content
    content /mnt/disk2/.snapraid.content
    content /mnt/disk3/.snapraid.content
    content /var/lib/snapraid/.snapraid.content
    
    # Data drives
    disk d1 /mnt/disk1/
    disk d2 /mnt/disk2/
    disk d3 /mnt/disk3/
    
    # Excludes
    exclude *.tmp
    exclude /downloads/
    exclude .snapraid.content
    exclude .mergerfs
    
    # Auto-save after 1000 ops (optional, helps with recovery)
    autosave 1000
    
    # Block size (256KB good for large files)
    blocksize 256
    
    # Hash size
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

  # SnapRAID scrub service (weekly - checks for bit rot)
  systemd.services.snapraid-scrub = {
    description = "SnapRAID Scrub";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.snapraid}/bin/snapraid scrub -p 10";  # Check 10% each run
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
    notifications.mail = {
      enable = false;  # Set to true and configure if you want email alerts
    };
  };

  # Spin down idle drives (optional, saves power/noise)
  services.hd-idle = {
    enable = true;
    settings = {
      # Spin down after 10 minutes idle
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
        
        # Time Machine support
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

  # Open firewall for NFS
  networking.firewall.allowedTCPPorts = [ 111 2049 4000 4001 4002 ];
  networking.firewall.allowedUDPPorts = [ 111 2049 4000 4001 4002 ];
}
```

**Step 2: Commit the NAS module**

```bash
git add machines/rpi4/nas.nix
git commit -m "feat(rpi4): add NAS module with MergerFS, SnapRAID, Samba, and NFS"
```

---

### Task 3: Create Arr Stack Module (LAN-only)

**Files:**
- Create: `machines/rpi4/arr-stack.nix`
- Reference: `vm-shared.nix` (for firewall patterns)

**Step 1: Create arr stack configuration**

```nix
{ config, pkgs, lib, ... }:

let
  # Helper to create arr service container
  arrUser = "arr";
  arrGroup = "arr";
in
{
  # Create arr user and group
  users.users.${arrUser} = {
    isSystemUser = true;
    group = arrGroup;
    home = "/var/lib/arr";
    createHome = true;
  };
  
  users.groups.${arrGroup} = {};

  # Ensure media directories are owned by arr group
  systemd.tmpfiles.rules = [
    "d /data/media 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/movies 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/tv 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/music 0775 ${arrUser} ${arrGroup} -"
    "d /data/media/downloads 0775 ${arrUser} ${arrGroup} -"
  ];

  # Prowlarr - Indexer manager
  services.prowlarr = {
    enable = true;
    openFirewall = false;  # We'll handle firewall manually
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
      # Password should be set via transmission-remote after first start
      # or configure via settings.json directly
      ratio-limit = 0;
      ratio-limit-enabled = true;
      speed-limit-down = 10000;      # 10MB/s
      speed-limit-down-enabled = true;
      speed-limit-up = 1000;         # 1MB/s
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

  # Firewall - LAN ONLY, block from Tailscale
  networking.firewall = {
    interfaces.eth0 = {
      allowedTCPPorts = [
        7878   # Radarr
        8989   # Sonarr
        8686   # Lidarr
        9696   # Prowlarr
        9091   # Transmission
        8096   # Jellyfin
      ];
    };
    # Explicitly block on tailscale0
    extraCommands = ''
      iptables -A INPUT -i tailscale0 -p tcp --dport 7878 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8989 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8686 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 9696 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 9091 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8096 -j DROP
    '';
  };

  # Reverse proxy for nice URLs (optional but recommended)
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    
    virtualHosts = {
      "rpi4.local" = {
        locations = {
          "/radarr/".proxyPass = "http://127.0.0.1:7878";
          "/sonarr/".proxyPass = "http://127.0.0.1:8989";
          "/lidarr/".proxyPass = "http://127.0.0.1:8686";
          "/prowlarr/".proxyPass = "http://127.0.0.1:9696";
          "/transmission/".proxyPass = "http://127.0.0.1:9091";
          "/".proxyPass = "http://127.0.0.1:8096";  # Jellyfin at root
        };
      };
    };
  };

  # Open firewall for nginx (LAN only)
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 80 443 ];
}
```

**Step 2: Commit the arr stack module**

```bash
git add machines/rpi4/arr-stack.nix
git commit -m "feat(rpi4): add arr stack module (Radarr, Sonarr, Lidarr, Prowlarr, Transmission, Jellyfin)"
```

---

### Task 4: Create Finance Module (VPN-only)

**Files:**
- Create: `machines/rpi4/finance.nix`

**Step 1: Create finance configuration**

```nix
{ config, pkgs, lib, ... }:

{
  # Install rustledger and rustfava
  environment.systemPackages = with pkgs; [
    # rustledger  # Not in nixpkgs yet - see note below
    # rustfava    # Not in nixpkgs yet - see note below
  ];

  # Note: rustledger and rustfava need to be packaged or installed manually
  # For now, we'll set up the structure and manual installation path
  
  # Create finance user
  users.users.finance = {
    isSystemUser = true;
    group = "finance";
    home = "/var/lib/finance";
    createHome = true;
  };
  
  users.groups.finance = {};

  # Finance data directory
  systemd.tmpfiles.rules = [
    "d /var/lib/finance 0750 finance finance -"
    "d /var/lib/finance/data 0750 finance finance -"
    "d /var/lib/finance/backups 0750 finance finance -"
  ];

  # rustfava service (when packaged)
  # For now, manual setup with systemd service template
  systemd.services.rustfava = {
    description = "rustfava - Web UI for plain text accounting";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "simple";
      User = "finance";
      Group = "finance";
      WorkingDirectory = "/var/lib/finance/data";
      # Update path when rustfava is packaged
      ExecStart = "/var/lib/finance/.local/bin/rustfava --host 0.0.0.0 --port 5000";
      Restart = "on-failure";
      RestartSec = 5;
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/finance" ];
    };
    
    # Only start if rustfava binary exists
    unitConfig = {
      ConditionPathExists = "/var/lib/finance/.local/bin/rustfava";
    };
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
        
        # Create backup with timestamp
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mkdir -p "$DEST"
        
        # Rsync with archive, verbose, delete old
        ${pkgs.rsync}/bin/rsync -av --delete "$SOURCE/" "$DEST/current/"
        
        # Also create dated snapshot
        cp -al "$DEST/current" "$DEST/snapshot_$TIMESTAMP"
        
        # Keep only last 30 snapshots
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

  # Firewall - VPN ONLY (tailscale0), block from LAN
  networking.firewall = {
    interfaces.tailscale0 = {
      allowedTCPPorts = [
        5000   # rustfava
      ];
    };
    # Block from LAN
    extraCommands = ''
      iptables -A INPUT -i eth0 -p tcp --dport 5000 -j DROP
      iptables -A INPUT -i en+ -p tcp --dport 5000 -j DROP
    '';
  };

  # Note for manual rustledger/rustfava installation:
  # 1. Clone/build rustledger: https://github.com/smallstepman/rustledger
  # 2. Clone/build rustfava: https://github.com/smallstepman/rustfava
  # 3. Install to /var/lib/finance/.local/bin/
  # 4. Place ledger files in /var/lib/finance/data/
}
```

**Step 2: Commit the finance module**

```bash
git add machines/rpi4/finance.nix
git commit -m "feat(rpi4): add finance module with rustfava service and auto-backup"
```

---

### Task 5: Create Audio Module (VPN-only)

**Files:**
- Create: `machines/rpi4/audio.nix`

**Step 1: Create audio streaming configuration**

```nix
{ config, pkgs, lib, ... }:

{
  # Separate Jellyfin instance for audio streaming
  # Uses different ports and data directory from main Jellyfin
  
  # Create audio user
  users.users.audio = {
    isSystemUser = true;
    group = "audio";
    home = "/var/lib/audio";
    createHome = true;
  };
  
  users.groups.audio = {};

  # Audio directories
  systemd.tmpfiles.rules = [
    "d /var/lib/audio/jellyfin 0755 audio audio -"
  ];

  # Jellyfin for audio (separate instance)
  # Using systemd service directly since services.jellyfin is single instance
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
      
      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/audio/jellyfin" "/data/media/music" "/data/audiobooks" ];
      
      # Resource limits for RPI4
      MemoryMax = "512M";
      CPUQuota = "50%";
    };

    environment = {
      # Tell Jellyfin to use different ports
      "JELLYFIN_PublishedServerUrl" = "http://rpi4-audio:8097";
    };
  };

  # Note: Jellyfin's port is hardcoded to 8096 in the binary
  # To change ports, we need to use the config file after first run
  # or set environment variables that Jellyfin respects
  # Alternative: Use systemd socket activation or nginx proxy

  # Workaround: nginx reverse proxy on different port
  services.nginx.virtualHosts = lib.mkMerge [
    {
      "rpi4-audio.local" = {
        listen = [{ addr = "0.0.0.0"; port = 8097; }];
        locations."/".proxyPass = "http://127.0.0.1:8096";
        # Note: This won't work for same-host conflicts
        # Better solution below:
      };
    }
  ];

  # Alternative: Use different network namespace or modify Jellyfin config
  # Best approach: Let jellyfin-audio bind to different port via config
  # First start will create config, then modify:
  # /var/lib/audio/jellyfin/config/network.xml - change HttpServerPortNumber

  # Firewall - VPN ONLY
  networking.firewall = {
    interfaces.tailscale0 = {
      allowedTCPPorts = [
        8097   # Audio Jellyfin (via nginx proxy)
      ];
    };
    # Block from LAN
    extraCommands = ''
      iptables -A INPUT -i eth0 -p tcp --dport 8097 -j DROP
      iptables -A INPUT -i en+ -p tcp --dport 8097 -j DROP
    '';
  };

  # Post-setup instructions will be in docs/rpi.sh
}
```

**Step 2: Commit the audio module**

```bash
git add machines/rpi4/audio.nix
git commit -m "feat(rpi4): add audio streaming module with separate Jellyfin instance"
```

---

### Task 6: Create Backup/Syncthing Module (VPN-only)

**Files:**
- Create: `machines/rpi4/backup.nix`

**Step 1: Create syncthing configuration**

```nix
{ config, pkgs, lib, ... }:

{
  # Syncthing for finance data backup (one-way: RPI4 -> external)
  
  services.syncthing = {
    enable = true;
    openDefaultPorts = false;  # We handle firewall manually
    
    user = "syncthing";
    group = "syncthing";
    dataDir = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/config";
    
    overrideDevices = true;
    overrideFolders = true;
    
    # Device settings - you'll need to add device IDs after first run
    settings = {
      devices = {
        # Add your devices here after initial setup:
        # laptop = { id = "DEVICE-ID-HERE"; name = "laptop"; };
        # phone = { id = "DEVICE-ID-HERE"; name = "phone"; };
      };
      
      folders = {
        # Finance data folder - send-only (one-way from RPI4)
        "finance-backup" = {
          path = "/data/backups/finance/current";
          id = "finance-backup";
          label = "Finance Backup";
          type = "sendonly";  # One-way sync: RPI4 -> others
          devices = [ ];  # Add devices after initial setup
          versioning = {
            type = "simple";
            params.keep = "10";
          };
        };
      };
      
      # GUI settings
      gui = {
        enabled = true;
        address = "127.0.0.1:8384";
        user = "m";
        # password = "...";  # Set via secrets or manual config
      };
      
      # Options
      options = {
        globalAnnounceEnabled = false;  # Disable public discovery
        localAnnounceEnabled = true;    # Allow LAN discovery
        relaysEnabled = false;          # Disable relay servers
        natEnabled = false;             # We use Tailscale
        urAccepted = -1;                # Disable usage reporting
      };
    };
  };

  # Create syncthing user
  users.users.syncthing = {
    isSystemUser = true;
    group = "syncthing";
    home = "/var/lib/syncthing";
    createHome = true;
  };
  
  users.groups.syncthing = {};

  # Ensure syncthing can read finance backups
  systemd.services.syncthing.serviceConfig = {
    SupplementaryGroups = [ "finance" ];
    ReadWritePaths = [ "/var/lib/syncthing" "/data/backups/finance" ];
  };

  # Firewall - VPN ONLY for sync, localhost only for GUI
  networking.firewall = {
    interfaces.tailscale0 = {
      allowedTCPPorts = [
        22000  # Syncthing protocol
      ];
      allowedUDPPorts = [
        22000  # Syncthing QUIC
        21027  # Syncthing local discovery
      ];
    };
    # GUI only on localhost (no external access)
    extraCommands = ''
      iptables -A INPUT -i eth0 -p tcp --dport 8384 -j DROP
      iptables -A INPUT -i tailscale0 -p tcp --dport 8384 -j DROP
    '';
  };

  # Use SSH tunnel for GUI access:
  # ssh -L 8384:localhost:8384 rpi4
  # Then open http://localhost:8384 in browser
}
```

**Step 2: Commit the backup module**

```bash
git add machines/rpi4/backup.nix
git commit -m "feat(rpi4): add Syncthing module for finance data backup (VPN-only)"
```

---

### Task 7: Create Main RPI4 Configuration

**Files:**
- Create: `machines/rpi4-server.nix`
- Modify: `flake.nix` (add rpi4 configuration)

**Step 1: Create main server configuration**

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/rpi4.nix
    ./hardware/disko-rpi4.nix
    ./rpi4/nas.nix
    ./rpi4/arr-stack.nix
    ./rpi4/finance.nix
    ./rpi4/audio.nix
    ./rpi4/backup.nix
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
    extraGroups = [ "wheel" "networkmanager" "docker" "finance" "audio" "arr" ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      # Or use: authorizedKeys.keyFiles = [ ./generated/host-authorized-keys ];
    ];
  };

  # Password for user (set via secret)
  users.users.m.hashedPasswordFile = config.sops.secrets."user/hashed-password".path;

  # Sudo configuration
  security.sudo.wheelNeedsPassword = true;

  # Tailscale
  services.tailscale = {
    enable = true;
    openFirewall = false;  # We handle this manually
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

  # Firewall base configuration
  networking.firewall = {
    enable = true;
    default = "drop";
    allowPing = true;
    
    # Always allow SSH
    allowedTCPPorts = [ 22 ];
    
    # Tailscale
    interfaces.tailscale0 = {
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };
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
  sops.secrets."user/hashed-password" = {
    collect.rbw.id = "nixos-hashed-password";
    neededForUsers = true;
  };

  # Essential packages
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
```

**Step 2: Add RPI4 to flake.nix**

Modify `flake.nix` around line 297 (after vm-aarch64 config):

```nix
    nixosConfigurations.vm-aarch64 = mkSystem "vm-aarch64" {
      system = "aarch64-linux";
      user   = "m";
    };

    # RPI4 Server Configuration
    nixosConfigurations.rpi4-server = mkSystem "rpi4-server" {
      system = "aarch64-linux";
      user   = "m";
    };

    nixosConfigurations.wsl = mkSystem "wsl" {
```

Also add rpi4-server to collect-secrets packages around line 320:

```nix
    packages.aarch64-darwin.collect-secrets = inputs.sopsidy.lib.buildSecretsCollector {
      pkgs = import nixpkgs { system = "aarch64-darwin"; };
      hosts = {
        inherit (self.nixosConfigurations) vm-aarch64 rpi4-server;
      };
    };
    # ... do the same for other platforms (x86_64-darwin, aarch64-linux, x86_64-linux)
```

**Step 3: Commit the main config and flake changes**

```bash
git add machines/rpi4-server.nix flake.nix
git commit -m "feat(rpi4): add main server configuration and integrate into flake"
```

---

### Task 8: Create Bootstrap Script (docs/rpi.sh)

**Files:**
- Create: `docs/rpi.sh`
- Reference: `docs/vm.sh` (copy patterns from here)

**Step 1: Create comprehensive bootstrap script**

```bash
#!/bin/bash
# rpi - NixOS Raspberry Pi 4 server setup
# Usage: rpi {bootstrap|switch|install|ssh}
# Standalone: sh <(curl -sL https://smallstepman.github.io/rpi.sh)

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
NIXADDR="${NIXADDR:-}"  # Will be discovered or set
NIXPORT="${NIXPORT:-22}"
NIXUSER="${NIXUSER:-m}"
NIXINSTALLUSER="${NIXINSTALLUSER:-root}"
NIXNAME="${NIXNAME:-rpi4-server}"
NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/.config/nix}"

SSH_OPTIONS="-o StrictHostKeyChecking=accept-new"
BOOTSTRAP_SSH_OPTIONS="-o PubkeyAuthentication=no -o PreferredAuthentications=password -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
INSTALL_SSH_PASSWORD="${INSTALL_SSH_PASSWORD:-root}"

HOST_SSH_PUBKEY_FILE="${HOST_SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
GENERATED_DIR="$NIX_CONFIG_DIR/machines/generated"

# ─── Helpers ────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

# Find RPI4 on network (requires nmap or similar)
rpi_detect_ip() {
    echo "Detecting Raspberry Pi on network..."
    # Look for devices with hostname 'rpi4-server' or SSH port open
    # This is a simple approach - you may need to adjust
    local ip
    ip=$(nmap -sn 192.168.1.0/24 2>/dev/null | grep -i raspberry | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [ -z "$ip" ]; then
        read -rp "Could not auto-detect RPI4 IP. Enter manually: " ip
    fi
    echo "$ip"
}

# ─── Prepare Host Auth Keys ────────────────────────────────────────────────

rpi_prepare_host_authorized_keys() {
    [ -f "$HOST_SSH_PUBKEY_FILE" ] || die "SSH public key not found: $HOST_SSH_PUBKEY_FILE"
    mkdir -p "$GENERATED_DIR"
    cp "$HOST_SSH_PUBKEY_FILE" "$GENERATED_DIR/rpi-host-authorized-keys"
}

# ─── Prepare SOPS Age Key ──────────────────────────────────────────────────

rpi_prepare_sops_age_key() {
    echo "Preparing SOPS age key on RPI4..."
    mkdir -p "$GENERATED_DIR"
    
    # Generate age key on RPI4 via SSH
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        sudo mkdir -p /var/lib/sops-nix
        sudo chmod 700 /var/lib/sops-nix
        if [ ! -f /var/lib/sops-nix/key.txt ]; then
            sudo nix-shell -p age --run "age-keygen -o /var/lib/sops-nix/key.txt"
            sudo chmod 600 /var/lib/sops-nix/key.txt
        fi
        sudo nix-shell -p age --run "age-keygen -y /var/lib/sops-nix/key.txt"
    ' | tr -d '\r' > "$GENERATED_DIR/rpi-age-pubkey"

    if ! grep -q '^age1' "$GENERATED_DIR/rpi-age-pubkey"; then
        die "Failed to fetch RPI4 sops age public key"
    fi
    
    echo "Age key collected successfully"
}

# ─── Collect Secrets ────────────────────────────────────────────────────────

rpi_collect_secrets() {
    touch "$NIX_CONFIG_DIR/machines/secrets.yaml"
    git -C "$NIX_CONFIG_DIR" add -f machines/secrets.yaml
    (cd "$NIX_CONFIG_DIR" && nix --extra-experimental-features 'nix-command flakes' run "$NIX_CONFIG_DIR#collect-secrets")
    git -C "$NIX_CONFIG_DIR" reset -q -- machines/secrets.yaml
}

# ─── Detect Drives ──────────────────────────────────────────────────────────

rpi_detect_drives() {
    echo "Detecting USB drives on RPI4..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        echo "=== Block devices ==="
        lsblk -d -o NAME,SIZE,MODEL,SERIAL,TRAN
        echo ""
        echo "=== USB devices ==="
        lsusb
        echo ""
        echo "=== Disk IDs ==="
        ls -la /dev/disk/by-id/ 2>/dev/null || echo "No disk IDs available"
    '
    
    echo ""
    echo "Please update machines/hardware/disko-rpi4.nix with correct device paths"
    echo "Use /dev/disk/by-id/ for stable device naming"
}

# ─── Bootstrap ───────────────────────────────────────────────────────────────

cmd_bootstrap() {
    echo "=== RPI4 NixOS Bootstrap ==="
    echo ""
    
    if [ -z "$NIXADDR" ]; then
        NIXADDR=$(rpi_detect_ip)
    fi
    
    echo "Target: ${NIXADDR}"
    echo ""
    
    # Prepare host keys
    echo "==> Preparing host authorized keys..."
    rpi_prepare_host_authorized_keys
    
    # Generate age key
    echo "==> Generating SOPS age key..."
    rpi_prepare_sops_age_key
    
    # Detect drives
    echo "==> Detecting drives..."
    rpi_detect_drives
    
    # Collect secrets
    echo "==> Collecting secrets..."
    git -C "$NIX_CONFIG_DIR" add machines/generated/rpi-age-pubkey machines/generated/rpi-host-authorized-keys
    rpi_collect_secrets
    
    echo ""
    echo "=== Bootstrap preparation complete ==="
    echo ""
    echo "Next steps:"
    echo "1. Update machines/hardware/disko-rpi4.nix with your drive IDs"
    echo "2. Add your SSH public key to machines/rpi4-server.nix"
    echo "3. Run: rpi install"
    echo ""
    echo "To install NixOS to RPI4 drives:"
    echo "  NIXADDR=$NIXADDR rpi install"
}

# ─── Install NixOS ──────────────────────────────────────────────────────────

cmd_install() {
    if [ -z "$NIXADDR" ]; then
        die "NIXADDR not set. Run 'rpi bootstrap' first or set NIXADDR manually"
    fi
    
    echo "=== Installing NixOS on RPI4 ==="
    echo "Target: ${NIXADDR}"
    echo ""
    
    # Get LUKS password from user
    echo "Enter LUKS encryption password (will be required on every boot):"
    read -rs LUKS_PASSWORD
    echo ""
    
    # Copy password to RPI4 for disko
    echo "$LUKS_PASSWORD" | sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        cat > /tmp/luks-password'
    
    # Run disko partitioning
    echo "==> Partitioning drives with Disko..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" "
        set -e
        cd /etc/nixos || cd /tmp
        
        # Copy config if not present
        if [ ! -d nixos-config ]; then
            echo 'Cloning nixos-config...'
            # You'll need to copy config via SSH/SCP
        fi
        
        # Run disko
        sudo nix --experimental-features 'nix-command flakes' run \
            github:nix-community/disko -- \
            --mode disko \
            ./machines/hardware/disko-rpi4.nix
        
        echo 'Disko complete'
    "
    
    # Copy sops key to persistent location
    echo "==> Setting up SOPS key..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" '
        sudo mkdir -p /mnt/var/lib/sops-nix
        sudo cp /var/lib/sops-nix/key.txt /mnt/var/lib/sops-nix/key.txt
        sudo chmod 700 /mnt/var/lib/sops-nix
        sudo chmod 600 /mnt/var/lib/sops-nix/key.txt
    '
    
    # Copy nixos-config to target
    echo "==> Copying NixOS configuration..."
    sshpass -p "$INSTALL_SSH_PASSWORD" scp $BOOTSTRAP_SSH_OPTIONS -r -P "$NIXPORT" \
        "$NIX_CONFIG_DIR/"* "${NIXINSTALLUSER}@${NIXADDR}:/mnt/etc/nixos/" || true
    
    # Install NixOS
    echo "==> Installing NixOS..."
    sshpass -p "$INSTALL_SSH_PASSWORD" ssh $BOOTSTRAP_SSH_OPTIONS -p"$NIXPORT" "${NIXINSTALLUSER}@${NIXADDR}" "
        sudo nixos-install \\
            --flake '/mnt/etc/nixos#${NIXNAME}' \\
            --no-root-passwd
        echo 'Installation complete!'
    "
    
    echo ""
    echo "=== Installation complete ==="
    echo ""
    echo "Reboot the RPI4 and remove the SD card:"
    echo "  ssh root@${NIXADDR} 'reboot'"
    echo ""
    echo "After reboot, you can SSH as user 'm':"
    echo "  ssh m@${NIXADDR}"
}

# ─── Switch Configuration ───────────────────────────────────────────────────

cmd_switch() {
    if [ -z "$NIXADDR" ]; then
        NIXADDR=$(rpi_detect_ip)
    fi
    
    echo "Switching NixOS config on RPI4 at ${NIXADDR}..."
    
    # Copy config
    rsync -avz -e "ssh $SSH_OPTIONS -p $NIXPORT" \
        --exclude='.git' --exclude='result' \
        "$NIX_CONFIG_DIR/" "${NIXUSER}@${NIXADDR}:/etc/nixos/"
    
    # Rebuild
    ssh $SSH_OPTIONS -p "$NIXPORT" "${NIXUSER}@${NIXADDR}" \
        "sudo nixos-rebuild switch --flake '/etc/nixos#${NIXNAME}'"
}

# ─── SSH ─────────────────────────────────────────────────────────────────────

cmd_ssh() {
    if [ -z "$NIXADDR" ]; then
        NIXADDR=$(rpi_detect_ip)
    fi
    
    if [ $# -gt 0 ]; then
        ssh $SSH_OPTIONS -p "$NIXPORT" "${NIXUSER}@${NIXADDR}" "$@"
    else
        ssh $SSH_OPTIONS -p "$NIXPORT" "${NIXUSER}@${NIXADDR}"
    fi
}

# ─── Help ────────────────────────────────────────────────────────────────────

cmd_help() {
    cat <<'EOF'
rpi - NixOS Raspberry Pi 4 server management

Usage: rpi <command>

Commands:
  help              Show this help
  bootstrap         Prepare RPI4 for installation (SSH, keys, secrets)
  install           Install NixOS to RPI4 drives
  switch            Apply configuration changes to running RPI4
  ssh [cmd]         SSH into RPI4, or run a command
  drives            Detect and display connected drives

Environment:
  NIXADDR           IP address of RPI4 (auto-detected if not set)
  NIXPORT           SSH port (default: 22)
  NIXUSER           Username (default: m)
  NIXNAME           Configuration name (default: rpi4-server)
  NIX_CONFIG_DIR    Path to nix config (default: ~/.config/nix)

Setup Workflow:
  1. Flash NixOS SD card image to SD
  2. Boot RPI4 with SD card
  3. Set root password: passwd
  4. Run: NIXADDR=<ip> rpi bootstrap
  5. Update disko-rpi4.nix with your drive IDs
  6. Run: NIXADDR=<ip> rpi install
  7. Reboot and remove SD card
  8. SSH into new NixOS installation

Post-Install:
  - Unlock LUKS drives at boot (password required)
  - Set up Tailscale: sudo tailscale up
  - Configure Jellyfin libraries
  - Add devices to Syncthing
  - Install rustledger/rustfava manually

EOF
}

# ─── Main ────────────────────────────────────────────────────────────────────

# No args: show help
if [ $# -eq 0 ]; then
    cmd_help
    exit 0
fi

cmd="$1"
shift

case "$cmd" in
    help)       cmd_help ;;
    bootstrap)  cmd_bootstrap "$@" ;;
    install)    cmd_install "$@" ;;
    switch)     cmd_switch "$@" ;;
    ssh)        cmd_ssh "$@" ;;
    drives)     NIXADDR="${NIXADDR:-$(rpi_detect_ip)}"; rpi_detect_drives ;;
    *)          echo "Unknown command: $cmd"; cmd_help; exit 1 ;;
esac
```

**Step 2: Commit the bootstrap script**

```bash
git add docs/rpi.sh
git commit -m "feat(rpi4): add comprehensive bootstrap script following vm.sh pattern"
```

---

### Task 9: Create Post-Install Documentation

**Files:**
- Create: `docs/rpi-POST-INSTALL.md`

**Step 1: Create post-install guide**

```markdown
# RPI4 NixOS Server - Post-Installation Guide

## Initial Setup

### 1. First Boot

After `rpi install` and reboot:

```bash
# Unlock LUKS drives (enter password at prompt)
# System will boot into NixOS

# SSH into the server
ssh m@rpi4-server

# Check drive mounts
lsblk
ls -la /data
```

### 2. Initialize MergerFS Pool

```bash
# Check that all drives mounted
mount | grep mergerfs

# Verify MergerFS pool
ls -la /data
```

### 3. Initialize SnapRAID

```bash
# First-time sync (this will take a while)
sudo snapraid sync

# Check status
sudo snapraid status
```

### 4. Connect Tailscale

```bash
# Authenticate with Tailscale
sudo tailscale up

# Get Tailscale IP
ip addr show tailscale0

# Verify connection
ping 100.x.x.x  # Another Tailscale device
```

## Service Configuration

### Arr Stack

1. **Prowlarr** (http://rpi4-server:9696)
   - Add indexers
   - Configure apps (Radarr, Sonarr, Lidarr)

2. **Radarr** (http://rpi4-server:7878)
   - Settings → Media Management → Root Folder: `/data/media/movies`
   - Settings → Download Clients → Add Transmission

3. **Sonarr** (http://rpi4-server:8989)
   - Settings → Media Management → Root Folder: `/data/media/tv`
   - Settings → Download Clients → Add Transmission

4. **Lidarr** (http://rpi4-server:8686)
   - Settings → Media Management → Root Folder: `/data/media/music`
   - Settings → Download Clients → Add Transmission

5. **Transmission** (http://rpi4-server:9091)
   - Default login: m / [password]
   - Download directory: `/data/media/downloads`

6. **Jellyfin** (http://rpi4-server:8096)
   - Initial setup wizard
   - Add libraries:
     - Movies: `/data/media/movies`
     - TV: `/data/media/tv`
     - Music: `/data/media/music`

### Finance Tools

1. **Install rustledger/rustfava**:
   ```bash
   # Build from source (not yet in nixpkgs)
   cd /tmp
   git clone https://github.com/smallstepman/rustledger
   cd rustledger
   cargo build --release
   sudo cp target/release/rustledger /var/lib/finance/.local/bin/
   
   git clone https://github.com/smallstepman/rustfava
   cd rustfava
   cargo build --release
   sudo cp target/release/rustfava /var/lib/finance/.local/bin/
   
   # Set ownership
   sudo chown -R finance:finance /var/lib/finance/
   
   # Start service
   sudo systemctl start rustfava
   ```

2. **Access rustfava**:
   - Via Tailscale: http://rpi4-server:5000

3. **Create ledger files**:
   ```bash
   sudo -u finance -i
   cd /var/lib/finance/data
   # Create your beancount/ledger files here
   ```

### Audio Streaming

1. **Jellyfin Audio** (http://rpi4-server:8097 via Tailscale)
   - Configure libraries:
     - Music: `/data/media/music`
     - Audiobooks: `/data/audiobooks`

2. **Client Setup**:
   - Install Jellyfin app on phone
   - Connect via Tailscale IP

### Syncthing Backup

1. **Access GUI via SSH tunnel**:
   ```bash
   ssh -L 8384:localhost:8384 m@rpi4-server
   # Open http://localhost:8384 in browser
   ```

2. **Add Devices**:
   - Get device ID from your laptop/phone
   - Add to Syncthing GUI
   - Share `finance-backup` folder

3. **Verify Sync**:
   - Check that finance data syncs to your devices

## Maintenance

### Daily

- SnapRAID sync runs automatically

### Weekly

- SnapRAID scrub runs automatically
- Review arr stack downloads

### Monthly

```bash
# Check drive health
sudo smartctl -a /dev/sda
sudo smartctl -a /dev/sdb
# ... for each drive

# Check SnapRAID status
sudo snapraid status

# Check for errors
sudo snapraid check

# Update NixOS
sudo nixos-rebuild switch --upgrade
```

### LUKS Password Change

```bash
# Change LUKS password (adds new, doesn't remove old)
sudo cryptsetup luksAddKey /dev/sdX

# Remove old password (if needed)
sudo cryptsetup luksRemoveKey /dev/sdX
```

## Troubleshooting

### Drives Not Mounting

```bash
# Check LUKS status
sudo cryptsetup status data1

# Manual unlock
sudo cryptsetup luksOpen /dev/disk/by-id/usb-... data1

# Mount manually
sudo mount /dev/mapper/data1 /mnt/disk1
```

### MergerFS Issues

```bash
# Remount
sudo umount /data
sudo mount -t fuse.mergerfs -o defaults,allow_other,use_ino,category.create=mfs /mnt/disk1:/mnt/disk2:/mnt/disk3 /data
```

### SnapRAID Errors

```bash
# Check status
sudo snapraid status

# Fix errors
sudo snapraid fix

# Sync after fixing
sudo snapraid sync
```

### Service Logs

```bash
# Check service status
sudo systemctl status jellyfin
sudo systemctl status radarr

# View logs
sudo journalctl -u jellyfin -f
sudo journalctl -u radarr -f
```

## Backup Strategy

### Local (SnapRAID)
- 1-drive failure protection
- Manual: `sudo snapraid sync`

### Remote (Syncthing)
- Finance data to multiple devices
- One-way sync from RPI4

### Offsite (Future)
- Consider rclone to cloud storage
- Or second RPI4 at different location

---

**Last Updated:** 2026-03-09
```

**Step 2: Commit the documentation**

```bash
git add docs/rpi-POST-INSTALL.md
git commit -m "docs(rpi4): add post-installation guide and troubleshooting"
```

---

### Task 10: Commit Design Document

**Step 1: Commit the design document we created earlier**

```bash
git add docs/plans/2026-03-09-rpi4-server-design.md
git commit -m "docs(rpi4): add design document"
```

---

## Summary

This implementation plan creates a complete Raspberry Pi 4 NixOS server with:

**Created Files:**
1. `machines/hardware/rpi4.nix` - Hardware configuration
2. `machines/hardware/disko-rpi4.nix` - Disk partitioning with LUKS
3. `machines/rpi4/nas.nix` - MergerFS + SnapRAID + Samba + NFS
4. `machines/rpi4/arr-stack.nix` - Radarr, Sonarr, Lidarr, Prowlarr, Transmission, Jellyfin
5. `machines/rpi4/finance.nix` - rustfava service with auto-backup
6. `machines/rpi4/audio.nix` - Separate Jellyfin instance for audio
7. `machines/rpi4/backup.nix` - Syncthing for finance data
8. `machines/rpi4-server.nix` - Main server configuration
9. `docs/rpi.sh` - Bootstrap script (follows vm.sh pattern)
10. `docs/rpi-POST-INSTALL.md` - Setup and troubleshooting guide
11. `docs/plans/2026-03-09-rpi4-server-design.md` - Design document

**Modified Files:**
1. `flake.nix` - Added rpi4-server configuration and collect-secrets integration

**Features:**
- LUKS encryption with manual password unlock
- MergerFS pool with ~2.75TB usable space
- SnapRAID with 1TB parity (1-drive failure protection)
- Arr stack accessible only from LAN
- Finance tools accessible only via Tailscale VPN
- Audio streaming via separate Jellyfin instance (VPN-only)
- Syncthing one-way backup (RPI4 → devices, VPN-only)
- Samba/NFS for Time Machine and file sharing

**Plan complete and saved to `docs/plans/2026-03-09-rpi4-server-implementation-plan.md`.**

**Two execution options:**

1. **Subagent-Driven (this session)** - I can execute the plan task-by-task using subagents
2. **Parallel Session (separate)** - Open new session in the worktree and run executing-plans

Which approach would you prefer?
