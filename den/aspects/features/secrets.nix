{ den, lib, generated, inputs, ... }: {

  den.aspects.secrets = {
    nixos = { config, pkgs, lib, ... }: {
      imports = [
        inputs.sops-nix.nixosModules.sops
        inputs.sopsidy.nixosModules.default
      ];

      sops.defaultSopsFile = generated.requireFile "secrets.yaml";

      sops.age.keyFile = "/var/lib/sops-nix/key.txt";
      sops.age.generateKey = true;
      sops.age.sshKeyPaths = [];
      sops.gnupg.sshKeyPaths = [];

      sops.secrets."tailscale/auth-key" = {
        collect.rbw.id = "tailscale-auth-key";
      };
      sops.secrets."rbw/email" = {
        collect.rbw.id = "bitwarden-email";
        owner = "m";
        mode = "0400";
      };
      sops.secrets."uniclip/password" = {
        collect.rbw.id = "uniclip-password";
        owner = "m";
        mode = "0400";
      };
      sops.secrets."user/hashed-password" = {
        collect.rbw.id = "nixos-hashed-password";
        neededForUsers = true;
      };

      services.tailscale.enable = true;
      services.tailscale.authKeyFile =
        config.sops.secrets."tailscale/auth-key".path;

      users.mutableUsers = false;

      users.users.m.hashedPasswordFile =
        config.sops.secrets."user/hashed-password".path;

      systemd.user.services.rbw-config = {
        description = "Write rbw config from sops secrets";
        after = [ "default.target" ];
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart =
            let
              script = pkgs.writeShellScript "write-rbw-config" ''
                set -euo pipefail
                email_file="/run/secrets/rbw/email"
                if [ ! -f "$email_file" ]; then
                  echo "rbw-config: $email_file not found, skipping" >&2
                  exit 0
                fi
                mkdir -p "$HOME/.config/rbw"
                ${pkgs.jq}/bin/jq -n \
                  --arg base_url "https://api.bitwarden.eu" \
                  --arg email "$(cat "$email_file")" \
                  --argjson lock_timeout 86400 \
                  --arg pinentry "${pkgs.wayprompt}/bin/pinentry-wayprompt" \
                  '{base_url: $base_url, email: $email, lock_timeout: $lock_timeout, pinentry: $pinentry}' \
                  > "$HOME/.config/rbw/config.json"
              '';
            in "${script}";
        };
      };
    };
  };

}
