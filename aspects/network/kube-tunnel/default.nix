{ ... }: let
  mkKubePassthroughBroker = pkgs: pkgs.writeShellApplication {
    name = "kubectl-passthrough-broker";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.kubectl pkgs.open-vm-tools ];
    text = ''
      set -euo pipefail
      source_kubeconfig="/nixos-generated/kubeconfig"
      local_kubeconfig="$HOME/.kube/config"
      state_dir="$HOME/.local/state/kubectl-passthrough"
      ports_file="$state_dir/ports.tsv"
      tunnels_dir="$state_dir/tunnels"
      last_source_hash=""
      declare -A brokered_clusters=()
      declare -A brokered_remotes=()
      declare -A desired_tunnels=()
      log() { printf 'kubectl-passthrough: %s\n' "$*" >&2; }
      cluster_hash() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
      brokerable_server() { case "$1" in https://127.0.0.1:*|https://localhost:*|https://192.168.130.1:*) return 0 ;; *) return 1 ;; esac; }
      remote_port_from_server() {
        local port="''${1##*:}"; port="''${port%%/*}"
        case "$port" in ""|*[!0-9]*) return 1 ;; *) printf '%s\n' "$port" ;; esac
      }
      port_for_cluster() {
        local cluster_name="$1" existing_port next_port
        if [ -f "$ports_file" ]; then
          existing_port=$(awk -F '\t' -v cluster="$cluster_name" '$1 == cluster { print $2; exit }' "$ports_file" || true)
          [ -n "$existing_port" ] && printf '%s\n' "$existing_port" && return 0
          next_port=$(awk -F '\t' 'BEGIN { max = 46442 } NF >= 2 && $2 + 0 > max { max = $2 + 0 } END { print max + 1 }' "$ports_file")
        else
          next_port=46443
        fi
        printf '%s\t%s\n' "$cluster_name" "$next_port" >> "$ports_file"
        printf '%s\n' "$next_port"
      }
      clear_broker_state() { brokered_clusters=(); brokered_remotes=(); desired_tunnels=(); }
      stop_stale_tunnels() {
        local pidfile hash pid remote_port local_port
        for pidfile in "$tunnels_dir"/*.pid; do
          [ -e "$pidfile" ] || continue
          hash=$(basename "$pidfile" .pid)
          if [ -z "''${desired_tunnels[$hash]+x}" ]; then
            read -r pid remote_port local_port < "$pidfile" || true
            [ -n "''${pid:-}" ] && kill -0 "$pid" 2>/dev/null && log "stopping stale tunnel $hash" && kill "$pid" 2>/dev/null || true
            rm -f "$pidfile" "$tunnels_dir/$hash.log"
          fi
        done
      }
      sync_local_kubeconfig() {
        local cluster_rows cluster_name server_url remote_port local_port cluster_hash tmp_kubeconfig
        cluster_rows=$(kubectl --kubeconfig "$source_kubeconfig" config view --raw -o jsonpath='{range .clusters[*]}{.name}{"\t"}{.cluster.server}{"\n"}{end}')
        clear_broker_state
        tmp_kubeconfig="$state_dir/kubeconfig.new"
        cp "$source_kubeconfig" "$tmp_kubeconfig"
        while IFS=$'\t' read -r cluster_name server_url; do
          [ -n "$cluster_name" ] || continue; [ -n "$server_url" ] || continue
          brokerable_server "$server_url" || continue
          remote_port=$(remote_port_from_server "$server_url") || { log "skipping cluster $cluster_name"; continue; }
          local_port=$(port_for_cluster "$cluster_name")
          cluster_hash=$(cluster_hash "$cluster_name")
          desired_tunnels["$cluster_hash"]=1
          brokered_clusters["$cluster_name"]="$local_port"
          brokered_remotes["$cluster_name"]="$remote_port"
          kubectl --kubeconfig "$tmp_kubeconfig" config set-cluster "$cluster_name" --server "https://127.0.0.1:$local_port" >/dev/null
        done <<< "$cluster_rows"
        chmod 600 "$tmp_kubeconfig"
        mv "$tmp_kubeconfig" "$local_kubeconfig"
      }
      reconcile_tunnels() {
        local cluster_name cluster_hash pidfile log_file pid stored_remote_port stored_local_port local_port remote_port
        mkdir -p "$tunnels_dir"
        for cluster_name in "''${!brokered_clusters[@]}"; do
          local_port="''${brokered_clusters[$cluster_name]}"
          remote_port="''${brokered_remotes[$cluster_name]}"
          cluster_hash=$(cluster_hash "$cluster_name")
          pidfile="$tunnels_dir/$cluster_hash.pid"
          log_file="$tunnels_dir/$cluster_hash.log"
          if [ -f "$pidfile" ]; then
            read -r pid stored_remote_port stored_local_port < "$pidfile" || true
            [ -n "''${pid:-}" ] && kill -0 "$pid" 2>/dev/null && [ "''${stored_remote_port:-}" = "$remote_port" ] && [ "''${stored_local_port:-}" = "$local_port" ] && continue
            [ -n "''${pid:-}" ] && kill -0 "$pid" 2>/dev/null && log "restarting tunnel for $cluster_name" && kill "$pid" 2>/dev/null || true
          fi
          log "starting tunnel for $cluster_name at 127.0.0.1:$local_port -> localhost:$remote_port"
          /run/current-system/sw/bin/ssh -N -T -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -L "127.0.0.1:''${local_port}:localhost:''${remote_port}" m@192.168.130.1 >> "$log_file" 2>&1 &
          printf '%s %s %s\n' "$!" "$remote_port" "$local_port" > "$pidfile"
        done
        stop_stale_tunnels
      }
      mkdir -p "$HOME/.kube" "$state_dir" "$tunnels_dir"
      shopt -s nullglob
      while true; do
        if vmware-hgfsclient | grep -Fqx nixos-generated && [ -f "$source_kubeconfig" ]; then
          current_source_hash=$(sha256sum "$source_kubeconfig" | awk '{print $1}')
          if [ "$current_source_hash" != "$last_source_hash" ]; then
            if sync_local_kubeconfig; then
              last_source_hash="$current_source_hash"
              reconcile_tunnels || log "tunnel reconciliation failed"
            else
              log "sync failed"
            fi
          else
            reconcile_tunnels
          fi
        else
          pidfiles=("$tunnels_dir"/*.pid)
          if [ -n "$last_source_hash" ] || [ -f "$local_kubeconfig" ] || [ "''${#pidfiles[@]}" -gt 0 ]; then
            clear_broker_state
            rm -f "$local_kubeconfig"
            reconcile_tunnels
          fi
          last_source_hash=""
        fi
        sleep 5
      done
    '';
  };
in {
  den.aspects.network.kube-tunnel = {
    homeManager = { pkgs, ... }: let
      kubePassthroughBroker = mkKubePassthroughBroker pkgs;
    in {
      systemd.user.services.kubectl-passthrough = {
        Unit = {
          Description = "Broker OrbStack Kubernetes tunnels through stable localhost ports";
          After = [ "default.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${kubePassthroughBroker}/bin/kubectl-passthrough-broker";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
  };
}
