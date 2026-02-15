{ pkgs, inputs, config, lib, ... }:

let
  hostAuthorizedKeysFile = ../../machines/generated/host-authorized-keys;
in

{
  # Write rbw config from sops-decrypted email (keeps email out of public repo)
  systemd.user.services.rbw-config = {
    description = "Write rbw config from sops secrets";
    after = [ "default.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = let
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
            --arg pinentry "${pkgs.pinentry-tty}/bin/pinentry-tty" \
            '{base_url: $base_url, email: $email, lock_timeout: $lock_timeout, pinentry: $pinentry}' \
            > "$HOME/.config/rbw/config.json"
        '';
      in "${script}";
    };
  };

  # Auto-unlock rbw (Bitwarden) vault on login using sops-decrypted master password
  systemd.user.services.rbw-unlock = {
    description = "Unlock rbw (Bitwarden) vault";
    after = [ "default.target" "rbw-config.service" ];
    requires = [ "rbw-config.service" ];
    wantedBy = [ "default.target" ];
    path = [ pkgs.rbw ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c 'if rbw unlocked >/dev/null 2>&1; then exit 0; fi; exec rbw unlock < /run/secrets/rbw/master-password'";
    };
  };

  systemd.user.timers.rbw-unlock-refresh = {
    description = "Keep rbw unlocked";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "rbw-unlock.service";
      OnBootSec = "5m";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };

  systemd.user.services.rbw-health-check = {
    description = "Check rbw unlock health";
    path = [ pkgs.rbw pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c 'state=locked; if rbw unlocked >/dev/null 2>&1; then state=unlocked; fi; mkdir -p \"$HOME/.local/state/rbw\"; printf \"%s %s\\n\" \"$(date --iso-8601=seconds)\" \"$state\" > \"$HOME/.local/state/rbw/health\"; test \"$state\" = unlocked'";
    };
  };

  systemd.user.timers.rbw-health-check = {
    description = "Periodic rbw unlock health checks";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      Unit = "rbw-health-check.service";
      OnBootSec = "10m";
      OnUnitActiveSec = "30m";
      Persistent = true;
    };
  };
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/zsh" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using zsh as our shell
  programs.zsh.enable = true;

  # We require this because we use lazy.nvim against the best wishes
  # a pure Nix system so this lets those unpatched binaries run.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  users.users.m = {
    isNormalUser = true;
    home = "/home/m";
    extraGroups = [ "docker" "lxd" "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    hashedPasswordFile = config.sops.secrets."user/hashed-password".path;
    openssh.authorizedKeys.keyFiles = [ hostAuthorizedKeysFile ];
  };
}
