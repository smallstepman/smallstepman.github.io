{ den, lib, generated, inputs, ... }: {

  den.aspects.secrets = {
    nixos = { config, pkgs, lib, ... }:
      let
        bridgePinentry = config.den.secrets.rbwPinentryPackage;
        rbwStaticSettings = builtins.toJSON (
          (builtins.removeAttrs config.home-manager.users.m.programs.rbw.settings [ "email" ])
          // (lib.optionalAttrs (config.home-manager.users.m.programs.rbw.settings ? pinentry) {
            pinentry = toString config.home-manager.users.m.programs.rbw.settings.pinentry;
          })
        );
      in {
      options.den.secrets.rbwPinentryPackage = lib.mkOption {
        type = with lib.types; nullOr package;
        default = null;
        description = "Host-specific rbw pinentry package used by the generated Linux rbw config.";
      };

      imports = [
        inputs.sops-nix.nixosModules.sops
        inputs.sopsidy.nixosModules.default
      ];

      config = {
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

        home-manager.users.m.programs.rbw.settings.pinentry =
          lib.mkIf (bridgePinentry != null) bridgePinentry;

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
                  tmp_config=$(mktemp "$HOME/.config/rbw/config.json.XXXXXX")
                  trap 'rm -f "$tmp_config"' EXIT
                  ${pkgs.jq}/bin/jq \
                    --arg email "$(cat "$email_file")" \
                    '.email = $email' <<'EOF' > "$tmp_config"
                  ${rbwStaticSettings}
                  EOF
                  mv "$tmp_config" "$HOME/.config/rbw/config.json"
                '';
              in "${script}";
          };
        };
      };
    };
  };

}
