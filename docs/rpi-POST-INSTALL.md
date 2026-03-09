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

# Verify MergerFS pool (~1.75TB usable)
ls -la /data
df -h /data
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
```

## Service Configuration

### Arr Stack (LAN-only)

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
   - Default login: m / [set password on first start]
   - Download directory: `/data/media/downloads`

6. **Jellyfin** (http://rpi4-server:8096)
   - Initial setup wizard
   - Add libraries:
     - Movies: `/data/media/movies`
     - TV: `/data/media/tv`
     - Music: `/data/media/music`

### Finance Stack (VPN-only via Tailscale)

1. **rustfava** is pre-installed via Nix
   - Access via Tailscale: http://rpi4-server:5000

2. **Create ledger files**:
   ```bash
   sudo -u finance -i
   cd /var/lib/finance/data
   # Create your beancount/ledger files here
   ```

### Audio Streaming (VPN-only via Tailscale)

1. **Jellyfin Audio** (http://rpi4-server:8097 via Tailscale)
   - Configure libraries:
     - Music: `/data/media/music`
     - Audiobooks: `/data/audiobooks`

### Syncthing Backup (VPN-only)

1. **Access GUI via SSH tunnel**:
   ```bash
   ssh -L 8384:localhost:8384 m@rpi4-server
   # Open http://localhost:8384 in browser
   ```

2. **Add Devices**:
   - Get device ID from your laptop/phone
   - Add to Syncthing GUI
   - Share `finance-backup` folder (one-way from RPI4)

## Maintenance

### Daily
- SnapRAID sync runs automatically

### Weekly
- SnapRAID scrub runs automatically

### Monthly
```bash
# Check drive health
sudo smartctl -a /dev/disk/by-id/usb-...

# Check SnapRAID status
sudo snapraid status

# Update NixOS
sudo nixos-rebuild switch --upgrade
```

## Troubleshooting

### Drives Not Mounting
```bash
# Check LUKS status
sudo cryptsetup status data1

# Manual unlock
sudo cryptsetup luksOpen /dev/disk/by-id/usb-... data1
```

### SnapRAID Errors
```bash
# Check status
sudo snapraid status

# Fix errors
sudo snapraid fix
sudo snapraid sync
```

### Service Logs
```bash
sudo journalctl -u jellyfin -f
sudo journalctl -u radarr -f
```

---

**Last Updated:** 2026-03-09
