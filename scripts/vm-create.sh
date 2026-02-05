#!/bin/bash
# Helper script for vm/create Makefile target
# Handles ISO version extraction, SHA256 checking, and downloading

set -e

VM_BASE_DIR="$HOME/Virtual Machines.localized"
NIXOS_ISO_URL="https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso"
NIXOS_ISO_SHA_URL="https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-aarch64-linux.iso.sha256"

# Check for vmrun
if ! command -v vmrun >/dev/null 2>&1; then
  echo "Error: vmrun not found. VMware Fusion is required."
  echo "Opening download page..."
  open "https://www.vmware.com/products/fusion.html"
  exit 1
fi

# Function to extract major.minor version from ISO filename
extract_version_from_iso() {
  local iso_file="$1"
  # Extract major.minor version (e.g., 25.11 from 25.11.5198.e576e3c9cf9b)
  if [[ "$iso_file" =~ nixos-minimal-([0-9]+\.[0-9]+)\. ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Function to download ISO with proper filename
download_iso() {
  local filename
  filename=$(curl -sI "$NIXOS_ISO_URL" | grep -i location | sed 's/.*\///' | tr -d '\r')
  if [ -z "$filename" ]; then
    filename="nixos-minimal-25.11-latest-aarch64-linux.iso"
  fi
  echo "Downloading latest NixOS ISO: $filename" >&2
  curl -L -o "$VM_BASE_DIR/$filename" "$NIXOS_ISO_URL"
  echo "$VM_BASE_DIR/$filename"
}

# Function to get remote SHA256 (follow redirects)
get_remote_sha() {
  curl -sL "$NIXOS_ISO_SHA_URL" | awk '{print $1}'
}

# Function to get local SHA256
get_local_sha() {
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

# Find existing ISO files
existing_iso=$(find "$VM_BASE_DIR" -name "nixos-minimal-*.iso" -type f 2>/dev/null | head -1)

if [ -n "$existing_iso" ]; then
  echo "Found existing ISO: $existing_iso"
  NIXOS_VERSION=$(extract_version_from_iso "$existing_iso")
  ISO_FILE="$existing_iso"

  # Check if we need to update by comparing SHA256
  echo "Checking for updates..."
  remote_sha=$(get_remote_sha)
  local_sha=$(get_local_sha "$ISO_FILE")

  if [ "$remote_sha" != "$local_sha" ]; then
    echo "SHA256 mismatch - downloading latest ISO..."
    echo "Remote SHA: $remote_sha"
    echo "Local SHA:  $local_sha"
    rm -f "$ISO_FILE"
    ISO_FILE=$(download_iso)
    NIXOS_VERSION=$(extract_version_from_iso "$ISO_FILE")
  else
    echo "ISO is up to date"
  fi
else
  echo "No existing ISO found, downloading latest..."
  ISO_FILE=$(download_iso)
  NIXOS_VERSION=$(extract_version_from_iso "$ISO_FILE")
fi

# Fallback version if extraction fails
if [ -z "$NIXOS_VERSION" ]; then
  NIXOS_VERSION="25.11"
fi

# Set VM name based on version
VM_NAME="NixOS ${NIXOS_VERSION} aarch64"
VM_DIR="$VM_BASE_DIR/${VM_NAME}.vmwarevm"
VMX_FILE="$VM_DIR/${VM_NAME}.vmx"

echo ""
echo "Creating VM: $VM_NAME"
echo "ISO: $ISO_FILE"
echo "VM Directory: $VM_DIR"

# Create VM directory
mkdir -p "$VM_DIR"

# Generate VMX file
cat >"$VMX_FILE" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "22"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
nvram = "${VM_NAME}.nvram"
virtualHW.productCompatibility = "hosted"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
displayName = "${VM_NAME}"
firmware = "efi"
guestOS = "arm-other6xlinux-64"
tools.syncTime = "TRUE"
tools.upgrade.policy = "upgradeAtPowerCycle"
sound.autoDetect = "TRUE"
sound.virtualDev = "hdaudio"
sound.fileName = "-1"
sound.present = "TRUE"
numvcpus = "7"
cpuid.coresPerSocket = "7"
memsize = "32656"
sata0.present = "TRUE"
nvme0.present = "TRUE"
nvme0:0.fileName = "Virtual Disk.vmdk"
nvme0:0.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "${ISO_FILE}"
sata0:1.present = "TRUE"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
ethernet0.addressType = "generated"
ethernet0.virtualDev = "e1000e"
ethernet0.linkStatePropagation.enable = "TRUE"
ethernet0.present = "TRUE"
extendedConfigFile = "${VM_NAME}.vmxf"
isolation.tools.hgfs.disable = "FALSE"
hgfs.mapRootShare = "TRUE"
hgfs.linkRootShare = "TRUE"
sharedFolder0.present = "TRUE"
sharedFolder0.enabled = "TRUE"
sharedFolder0.readAccess = "TRUE"
sharedFolder0.writeAccess = "TRUE"
sharedFolder0.hostPath = "$VM_BASE_DIR/Sync"
sharedFolder0.guestName = "Sync"
sharedFolder0.expiration = "never"
sharedFolder.maxNum = "1"
floppy0.present = "FALSE"
mks.enable3d = "TRUE"
svga.graphicsMemoryKB = "4194304"
gui.fitGuestUsingNativeDisplayResolution = "TRUE"
vmxstats.filename = "${VM_NAME}.scoreboard"
svga.vramSize = "268435456"
EOF

# Create auxiliary files
touch "$VM_DIR/${VM_NAME}.nvram"
echo '<?xml version="1.0"?><Foundry><VM><VMId type="string">'$(uuidgen)'</VMId></VM></Foundry>' >"$VM_DIR/${VM_NAME}.vmxf"
touch "$VM_DIR/${VM_NAME}.scoreboard"

# Create virtual disk
echo ""
echo "Creating virtual disk..."
if command -v vmware-vdiskmanager >/dev/null 2>&1; then
  vmware-vdiskmanager -c -s 100GB -a nvme -t 0 "$VM_DIR/Virtual Disk.vmdk"
elif [ -f "/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager" ]; then
  "/Applications/VMware Fusion.app/Contents/Library/vmware-vdiskmanager" -c -s 100GB -a nvme -t 0 "$VM_DIR/Virtual Disk.vmdk"
else
  echo "⚠ vmware-vdiskmanager not found. Create disk manually:"
  echo "   vmware-vdiskmanager -c -s 100GB -a nvme -t 0 \"$VM_DIR/Virtual Disk.vmdk\""
fi

echo ""
echo "✓ VM created successfully!"
echo "   VM: $VM_NAME"
echo "   Location: $VM_DIR"
echo "   ISO: $ISO_FILE"
echo "   CPU cores count: 7"
echo "   RAM: 32GB"
echo "   VRAM: 8GB"
echo "   NVMe: 150GB"
echo "   Network: autodetect"
echo ""
echo "To start the VM (should start automatically):"
echo "   open '$VMX_FILE'"
echo "   or"
echo "   vmrun start '$VMX_FILE'"
echo ""
echo "Next steps:"
echo "   1. Inside VM, in console run 'sudo su' then 'passwd' and set password for root user as 'root'."
echo "   2. Inside VM, in console run 'ip a' and take note of the IP address for the second entry 'enp2s0' or similar (~192.168.0.x)."
echo "   3. In your host terminal, run 'NIXADDR=<IP_ADDRESS_FROM_STEP_2> make vm/install' to install NixOS on the VM's virtual disk."

vmrun start "$VMX_FILE"
