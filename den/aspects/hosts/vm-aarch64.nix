# den/aspects/hosts/vm-aarch64.nix
#
# Host aspect for the vm-aarch64 (vm-macbook) NixOS machine.
#
# Wires den-native feature aspects (linux-core, secrets) and owns the
# host-specific remnants that do not belong in any reusable feature aspect:
#   - Hostname provisioning
#   - Host age pubkey for sops secret collection
#   - 127.0.0.1 hosts entry for vm-macbook
#   - openwebui-local-proxy systemd service
#   - users.users.m host-specific settings (extraGroups, authorizedKeys)
{ den, ... }: {
  den.aspects.vm-aarch64 = {
    includes = [
      # Core Linux system behavior (non-desktop, non-WSL-specific).
      den.aspects.linux-core

      # Secret-backed system settings (sops, Tailscale, user password, rbw).
      den.aspects.secrets

      # Hostname battery: sets networking.hostName from den.hosts config.
      den.provides.hostname

      # Host-specific NixOS configuration that does not belong in a shared aspect.
      ({ host, ... }: {
        nixos = { config, pkgs, lib, ... }: {

          # Host-specific sops age public key used by secret collection.
          sops.hostPubKey = lib.removeSuffix "\n"
            (builtins.readFile ../../../machines/generated/vm-age-pubkey);

          # Ensure vm-macbook resolves locally regardless of DNS state.
          networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];

          # Expose a tunneled Open WebUI instance on localhost:80.
          systemd.services.openwebui-local-proxy = {
            description = "Expose tunneled Open WebUI on localhost:80";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:80,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:18080";
              Restart = "always";
              RestartSec = 1;
            };
          };

          # User m: host-specific group membership and SSH authorized keys.
          # Note: wheel and networkmanager are already added by den.provides.primary-user;
          # only add the vm-aarch64-specific lxd group here to avoid duplicates.
          users.users.m = {
            extraGroups = [ "lxd" ];
            openssh.authorizedKeys.keyFiles = [
              ../../../machines/generated/host-authorized-keys
            ];
          };
        };
      })
    ];
  };
}
