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

### LLM Inference with Ollama

Run large language models locally on your NVIDIA GPU:

```bash
# List available models
./docs/x1e.sh ollama list

# Pull a model
./docs/x1e.sh ollama pull llama3.2

# Run a model (interactive chat)
./docs/x1e.sh ollama run llama3.2

# Run with custom prompt
./docs/x1e.sh ollama run llama3.2 "What is Kubernetes?"
```

**Popular Models:**
- `llama3.2` - Meta's latest (3B params, fast)
- `mistral` - High quality (7B params)
- `codellama` - Code generation
- `mixtral` - MoE architecture (47B params, needs more VRAM)

**API Access:**
```bash
# Ollama API is available via Tailscale
curl http://x1-homelab:11434/api/generate -d '{
  "model": "llama3.2",
  "prompt": "Explain quantum computing"
}'
```

**To Disable:** Comment out `services.ollama` in the configuration.

### Monitoring & Dashboards

The system includes Prometheus + Grafana for monitoring:

```bash
# Open all dashboards locally
./docs/x1e.sh dashboard

# Then access:
#   Grafana:     http://localhost:3000 (login: admin/admin)
#   Prometheus:  http://localhost:9090
#   Ollama API:  http://localhost:11434
#   k3s API:     https://localhost:6443
```

**Grafana Dashboards:**
- Node Exporter - CPU, memory, disk metrics
- NVIDIA DCGM - GPU utilization, temperature, memory
- Custom dashboards can be added via UI

**To Disable:** Comment out `services.prometheus` and `services.grafana` sections.

### GitOps with Flux CD

Deploy Kubernetes apps declaratively from Git:

```bash
# Bootstrap Flux with your GitHub repo
./docs/x1e.sh flux-bootstrap <your-github-username> <homelab-gitops>

# Example:
# ./docs/x1e.sh flux-bootstrap johndoe homelab-k8s
```

**Workflow:**
1. Bootstrap Flux (one-time setup)
2. Add Kubernetes manifests to your repo under `clusters/x1-homelab/`
3. Push to Git
4. Flux automatically applies changes to the cluster

**Example Directory Structure:**
```
homelab-gitops/
├── clusters/
│   └── x1-homelab/
│       ├── namespace.yaml
│       ├── deployment.yaml
│       └── kustomization.yaml
```

**Benefits:**
- Git as single source of truth
- Drift detection (alerts if cluster diverges)
- Automatic sync on push
- Disaster recovery (rebuild from Git)

**To Disable:** Comment out `services.fluxcd` in the configuration.

### Tailscale Access

The k3s API is accessible via Tailscale:
```
https://x1-homelab:6443
```

Services exposed via Kubernetes Ingress are available on your tailnet.

## Maintenance

### Helper Commands

The `x1e.sh` script provides convenient commands:

```bash
# Core commands
./docs/x1e.sh install <ip>    # Install NixOS on fresh machine
./docs/x1e.sh switch          # Apply config changes
./docs/x1e.sh setup-k3s       # Setup k3s + NVIDIA support
./docs/x1e.sh ssh             # SSH into machine

# GPU & Monitoring
./docs/x1e.sh gpu             # Show GPU status (nvidia-smi)
./docs/x1e.sh dashboard       # Port forward dashboards to localhost
./docs/x1e.sh logs            # Follow k3s logs in real-time
./docs/x1e.sh k9s             # Launch k9s terminal UI

# LLM
./docs/x1e.sh ollama list     # List LLM models
./docs/x1e.sh ollama run <model>  # Run a model

# GitOps
./docs/x1e.sh flux-bootstrap <owner> <repo>  # Setup Flux CD
```

### System Updates

Automatic updates are enabled by default (runs daily at 4 AM). To update manually:

```bash
# Update flake inputs
nix flake update

# Apply updates
./docs/x1e.sh switch
```

**To Disable Auto-Updates:** Comment out `system.autoUpgrade` in the configuration.

### Check GPU Health

```bash
# Quick GPU status
./docs/x1e.sh gpu

# Interactive GPU monitor (like htop)
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
