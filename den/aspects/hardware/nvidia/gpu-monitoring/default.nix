{ config, pkgs, lib, ... }: {
  den.aspects.hardware.nvidia.gpu-monitoring = {
    nixos = { config, pkgs, lib, ... }: {
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
          Type = "simple"; Restart = "always"; RestartSec = "5"; User = "root";
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
              done < <(${pkgs.pciutils}/bin/lspci -D | grep -i nvidia | awk '{print $1}')
              mv "$TMP" /var/lib/node_exporter/gpu.prom
              sleep 30
            done
          '';
        };
      };

      systemd.services.nvidia-xid-exporter = {
        description = "NVIDIA Xid Exporter";
        serviceConfig = {
          Type = "simple"; Restart = "always";
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
    };
  };
}
