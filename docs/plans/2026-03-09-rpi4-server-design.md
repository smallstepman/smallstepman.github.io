# Raspberry Pi 4 NixOS Server Design

> Design for a headless NixOS server running on Raspberry Pi 4 with NAS, media stack, finance tools, and audio streaming.

**Date:** 2026-03-09  
**Status:** Approved  
**Target:** RPI4 (8GB RAM recommended, 4GB minimum)

---

## Overview

A headless NixOS server providing:
1. **NAS** - Encrypted storage pool with redundancy (MergerFS + SnapRAID)
2. **Arr Stack** - Media automation (Radarr, Sonarr, Lidarr, Prowlarr, Transmission, Jellyfin)
3. **Finance Tools** - rustledger + rustfava for personal accounting
4. **Audio Streaming** - Jellyfin for music and audiobooks
5. **Backup** - Syncthing for finance data replication

---

## Hardware

### Drives

| Drive | Capacity | Role | Connection |
|-------|----------|------|------------|
| SD Card | 32GB+ | Boot + Bootstrap | Built-in slot |
| SSD A | 1TB | SnapRAID Parity | USB 3.0 |
| SSD B | 250GB | Data | USB 3.0 |
| HDD | 1TB | Data | USB 3.0 |
| NVMe (USB) | 500GB | Data | USB 3.0 |

**Total Pool:** ~2.75TB usable with 1-drive failure protection

### Boot Strategy

Following `docs/vm.sh` pattern:
1. Flash minimal NixOS SD card image
2. Boot RPI4, enable SSH
3. Bootstrap: secrets collection, SSH key setup
4. Disko partitioning with LUKS encryption
5. Install NixOS to target drives
6. Post-install: remove SD card, boot from USB

---

## Storage Architecture

### Encryption

All data drives LUKS-encrypted with password unlock at boot:
- Keys stored in `/etc/luks-keys/` (will need manual entry)
- Root partition may remain unencrypted for headless boot
- Data partitions encrypted with user-provided password

### Pooling (MergerFS)

```
/data
├── media/
│   ├── movies/
│   ├── tv/
│   ├── music/
│   └── downloads/
├── audiobooks/
└── backups/
    ├── finance/
    └── timemachine/
```

**MergerFS Policy:** `mfs` (most free space) for writes, `ff` (first found) for reads

### Redundancy (SnapRAID)

- 1TB SSD as parity drive
- Daily sync via systemd timer
- Scrub monthly to detect bit rot

---

## Service Architecture

### Network Zones

| Zone | Interface | Access |
|------|-----------|--------|
| **LAN** | `eth0` | Arr stack, Transmission, Jellyfin (Media) |
| **VPN** | `tailscale0` | Finance, Audio, Syncthing |

### Services

#### 1. NAS Services

**Samba (SMB)**
- Shares: `media`, `backups`, `audiobooks`
- Time Machine support enabled
- Guest access disabled

**NFS**
- Export `/data` to LAN clients
- Kerberos optional (not required for home use)

#### 2. Arr Stack (LAN Only)

| Service | Port | Description |
|---------|------|-------------|
| Radarr | 7878 | Movie management |
| Sonarr | 8989 | TV management |
| Lidarr | 8686 | Music management |
| Prowlarr | 9696 | Indexer aggregator |
| Transmission | 9091 | Torrent client |
| Jellyfin (Media) | 8096 | Media server |

**Firewall:** Explicitly block these ports on `tailscale0`

#### 3. Finance Stack (VPN Only)

| Service | Port | Description |
|---------|------|-------------|
| rustledger | N/A | CLI tool |
| rustfava | 5000 | Web UI for ledger |

**Firewall:** Allow only on `tailscale0`, block on `eth0`

**Backup Strategy:**
- Cron job: rsync `/var/lib/finance/` → `/data/backups/finance/`
- Syncthing: one-way sync from `/data/backups/finance/` to external devices

#### 4. Audio Streaming (VPN Only)

| Service | Port | Description |
|---------|------|-------------|
| Jellyfin (Audio) | 8097 | Separate instance for music/audiobooks |

**Note:** Separate Jellyfin instance to isolate media libraries

#### 5. Backup (VPN Only)

| Service | Port | Description |
|---------|------|-------------|
| Syncthing | 8384 (GUI), 22000 (sync) | Finance data sync |

**Direction:** RPI4 → External devices only (one-way)

---

## Security

### Firewall Rules

```
# LAN services - allow from LAN only
iptables -A INPUT -i eth0 -p tcp --dport 7878 -j ACCEPT  # Radarr
iptables -A INPUT -i tailscale0 -p tcp --dport 7878 -j DROP

# VPN services - allow from VPN only
iptables -A INPUT -i tailscale0 -p tcp --dport 5000 -j ACCEPT  # Fava
iptables -A INPUT -i eth0 -p tcp --dport 5000 -j DROP
```

### Tailscale

- Auth key from sops secrets
- Automatic NAT traversal
- Optional: ACLs for device isolation

### LUKS

- Password-protected volumes
- No keyfiles stored on disk
- Manual unlock required on each boot

---

## File Structure

```
machines/
├── hardware/
│   └── rpi4.nix              # Hardware-specific config
├── hardware/disko-rpi4.nix   # Disk partitioning
├── rpi4-server.nix           # Main server config
├── rpi4/
│   ├── nas.nix               # MergerFS + SnapRAID
│   ├── arr-stack.nix         # Radarr, Sonarr, etc.
│   ├── finance.nix           # rustledger, rustfava
│   ├── audio.nix             # Jellyfin audio
│   └── backup.nix            # Syncthing
└── secrets.yaml              # Encrypted secrets

docs/
├── rpi.sh                    # Bootstrap script (follows vm.sh pattern)
└── plans/
    └── 2026-03-09-rpi4-server-design.md  # This file
```

---

## Implementation Notes

### Raspberry Pi 4 Specifics

- Use `boot.loader.generic-extlinux-compatible` (not systemd-boot)
- Enable GPU memory split for headless (16MB)
- USB boot requires firmware update on older RPI4s
- Consider `boot.kernelParams = [ "console=ttyS0,115200n8" ];` for serial debugging

### LUKS + Headless Boot

Challenge: LUKS requires password entry, but RPI4 is headless.

**Solutions:**
1. Keep root unencrypted, encrypt only data partitions
2. Use Dropbear SSH in initrd for remote unlock
3. Small unencrypted boot partition, encrypted root

**Chosen:** Option 1 - Root on SD card or unencrypted USB, data partitions encrypted.

### Power Management

- RPI4 8GB can power 4 USB drives if using powered USB hub
- Consider: USB hub with 2.5A+ per port
- Monitor with `vcgencmd` for undervoltage

---

## Success Criteria

- [ ] RPI4 boots successfully from USB (after SD bootstrap)
- [ ] All 4 drives mount with LUKS encryption
- [ ] MergerFS pool accessible at `/data`
- [ ] SnapRAID sync and scrub work
- [ ] Arr stack accessible only from LAN
- [ ] Finance tools accessible only via Tailscale
- [ ] Audio streaming works over VPN
- [ ] Syncthing syncs finance data one-way
- [ ] Time Machine backups work to NAS

---

## Future Enhancements

- [ ] UPS integration (power-loss protection)
- [ ] SMART monitoring with notifications
- [ ] Automated SnapRAID scrub scheduling
- [ ] Monitoring dashboard (Grafana/Prometheus)
- [ ] Offsite backup to cloud (rclone)
- [ ] Wake-on-LAN for remote power-on

---

**Design Approved:** 2026-03-09
