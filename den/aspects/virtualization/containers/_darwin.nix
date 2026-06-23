{ pkgs, ... }: let
  kubeconfigGeneratedDir = "/Users/m/.local/share/nix-config-generated";
  kubeconfigBitwardenItem = "orbstack-kubeconfig";
  kubeconfigTarget = "${kubeconfigGeneratedDir}/kubeconfig";

  orbstackKubeconfigSync = pkgs.writeShellApplication {
    name = "orbstack-kubeconfig-sync";
    runtimeInputs = [ pkgs.coreutils pkgs.rbw ];
    text = ''
      set -euo pipefail
      umask 077
      mkdir -p ${kubeconfigGeneratedDir}
      tmp_kubeconfig=$(mktemp ${kubeconfigTarget}.XXXXXX)
      trap 'rm -f "$tmp_kubeconfig"' EXIT
      if ! rbw get ${kubeconfigBitwardenItem} > "$tmp_kubeconfig"; then
        echo "orbstack-kubeconfig-sync: failed to fetch ${kubeconfigBitwardenItem} from Bitwarden" >&2
        exit 1
      fi
      if [ ! -s "$tmp_kubeconfig" ]; then
        echo "orbstack-kubeconfig-sync: empty kubeconfig from Bitwarden item ${kubeconfigBitwardenItem}" >&2
        exit 1
      fi
      chmod 600 "$tmp_kubeconfig"
      if ! cmp -s "$tmp_kubeconfig" ${kubeconfigTarget} 2>/dev/null; then
        mv "$tmp_kubeconfig" ${kubeconfigTarget}
      fi
    '';
  };
in {
  homebrew.casks = [ "orbstack" ];
  launchd.user.agents.orbstack-kubeconfig-sync = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          set -euo pipefail
          /bin/wait4path /nix/store
          export PATH=${pkgs.rbw}/bin:/opt/homebrew/bin:$PATH
          exec ${orbstackKubeconfigSync}/bin/orbstack-kubeconfig-sync
        ''
      ];
      RunAtLoad = true;
      StartInterval = 300;
      StandardOutPath = "/tmp/orbstack-kubeconfig-sync.log";
      StandardErrorPath = "/tmp/orbstack-kubeconfig-sync.log";
    };
  };
}
