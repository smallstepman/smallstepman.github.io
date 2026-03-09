# ThinkPad X1 Extreme Gen1 k3s Homelab

NixOS-based Kubernetes homelab running on ThinkPad X1 Extreme Gen1 with dual-GPU setup: Intel UHD for desktop, NVIDIA GTX 1050 for ML/AI workloads.

## Hardware

- **Host:** ThinkPad X1 Extreme Gen1
- **CPU:** Intel Core i7-8750H (6C/12T)
- **iGPU:** Intel UHD Graphics 630 (desktop/display)
- **dGPU:** NVIDIA GeForce GTX 1050 Ti Max-Q 4GB (compute)
- **RAM:** 32GB+ DDR4 recommended
- **Storage:** NVMe SSD

## Features

- **Desktop:** Niri Wayland compositor using Intel GPU
- **Kubernetes:** k3s single-node cluster
- **GPU Compute:** NVIDIA GTX 1050 for ML/AI workloads
- **Networking:** Tailscale for secure remote access
- **Configuration:** Fully declarative with NixOS
- **Secrets:** Automated with sops-nix + sopsidy

## GPU Architecture

This setup uses **PRIME offload**:
- **Intel UHD 630:** Handles all display output, runs Niri desktop
- **NVIDIA GTX 1050:** Available for compute workloads (CUDA, ML, LLM inference)

Run GPU workloads with:
```bash
nvidia-offload <command>  # Offload to NVIDIA GPU
nvidia-smi                # Check GPU status
```

## Installation

### Prerequisites

- NixOS installer USB
- Tailscale auth key in Bitwarden
- SSH key pair

### 1. Create NixOS Installer USB

On a Nix system:
```bash
nix run nixpkgs#nixos-generators -- --format iso --configuration ./installer.nix -o nixos-thinkpad.iso
# Flash to USB: dd if=nixos-thinkpad.iso of=/dev/sdX bs=4M status=progress
```

### 2. Boot and Install

1. Boot ThinkPad from USB (hold F12 during boot)
2. Set root password: `passwd`
3. From another machine:

```bash
cd ~/.config/nix
./docs/x1e.sh prepare
./docs/x1e.sh install <thinkpad-ip>
```

The install script will:
- Partition and format the NVMe drive
- Copy your NixOS configuration
- Generate age keys for secrets
- Install NixOS

### 3. Post-Install Setup

After the ThinkPad reboots:

```bash
export NIXADDR=<thinkpad-tailscale-ip-or-local-ip>

# Setup k3s with NVIDIA support
./docs/x1e.sh setup-k3s

# Verify everything
./docs/x1e.sh ssh nvidia-smi          # Check GPU
./docs/x1e.sh ssh kubectl get nodes   # Check k3s
./docs/x1e.sh ssh tailscale status    # Check Tailscale
```

## Usage

### SSH Access

```bash
# Interactive SSH
./docs/x1e.sh ssh

# Run command
./docs/x1e.sh ssh nvidia-smi
./docs/x1e.sh ssh kubectl get pods -A
```

### Configuration Updates

```bash
# Make changes to machines/thinkpad-x1-extreme-gen1.nix
# Then apply:
./docs/x1e.sh switch
```

### GPU Workloads

#### Docker
```bash
# Run container with GPU access
docker run --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

#### Kubernetes
```bash
# Apply GPU test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
spec:
  containers:
  - name: cuda
    image: nvidia/cuda:11.8.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Check pod logs
kubectl logs gpu-test
```

#### Local GPU Offload
```bash
# Run command on NVIDIA GPU
nvidia-offload python train.py
nvidia-offload ollama run llama2
```

### Tailscale Access

The k3s API is accessible via Tailscale:
```
https://x1-homelab:6443
```

Services exposed via Kubernetes Ingress are available on your tailnet.

## Maintenance

### System Updates

```bash
# Update flake inputs
nix flake update

# Apply updates
./docs/x1e.sh switch
```

### Check GPU Health

```bash
./docs/x1e.sh ssh nvidia-smi
./docs/x1e.sh ssh nvtop
```

### Check k3s Status

```bash
./docs/x1e.sh ssh systemctl status k3s
./docs/x1e.sh ssh kubectl get nodes
./docs/x1e.sh ssh kubectl top nodes
```

### Collect Secrets

Add new secrets to `machines/secrets.yaml`:

```bash
# After updating secrets.yaml
nix run .#collect-secrets

# Commit and apply
./docs/x1e.sh switch
```

## Troubleshooting

### NVIDIA Driver Issues

If `nvidia-smi` fails:
```bash
# Check driver loaded
lsmod | grep nvidia

# Check Xorg logs
journalctl -u display-manager

# Rebuild with explicit module
sudo nixos-rebuild switch --flake '.#thinkpad-x1-extreme-gen1'
```

### k3s Not Starting

```bash
# Check service status
systemctl status k3s

# Check logs
journalctl -u k3s -f

# Reset (WARNING: destroys cluster data)
sudo rm -rf /var/lib/rancher/k3s
sudo systemctl restart k3s
```

### GPU Not Available in Pods

```bash
# Verify device plugin
kubectl get pods -n kube-system | grep nvidia

# Restart device plugin
kubectl delete pod -n kube-system -l name=nvidia-device-plugin
```

### Desktop (Niri) Issues

```bash
# Check session status
systemctl status greetd

# Check Wayland compositor
journalctl --user -u niri
```

## Architecture Details

### File Structure

```
~/.config/nix/
├── machines/
│   ├── thinkpad-x1-extreme-gen1.nix      # Main machine config
│   ├── hardware/
│   │   ├── thinkpad-x1-extreme-gen1.nix  # Hardware scan
│   │   └── disko-thinkpad-x1-extreme.nix # Disk partitioning
│   └── generated/
│       └── x1e-age-pubkey                # Age key for secrets
├── docs/
│   └── x1e.sh                            # Installation script
└── flake.nix                             # Flake with machine definition
```

### NVIDIA PRIME Configuration

The configuration uses PRIME offload mode:
- Intel GPU (`PCI:0@0:2:0`) renders the desktop
- NVIDIA GPU (`PCI:1@0:0:0`) available for compute
- `nvidia-offload` wrapper sets environment variables to use dGPU

See: [NixOS NVIDIA Wiki](https://wiki.nixos.org/wiki/NVIDIA)

### k3s Container Runtime

- **Runtime:** containerd (not Docker)
- **NVIDIA Support:** nvidia-container-runtime
- **Device Plugin:** NVIDIA k8s-device-plugin
- **CNI:** Flannel (k3s default)

## References

- [NixOS NVIDIA Configuration](https://wiki.nixos.org/wiki/NVIDIA)
- [NixOS k3s Module](https://search.nixos.org/options?query=services.k3s)
- [k3s Documentation](https://docs.k3s.io/)
- [NVIDIA Device Plugin](https://github.com/NVIDIA/k8s-device-plugin)
- [Niri Compositor](https://github.com/YaLTeR/niri)
