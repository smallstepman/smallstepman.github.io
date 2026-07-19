let
  configDir = builtins.getEnv "NIX_CONFIG_DIR";
  ageKeyFile = builtins.getEnv "VM_AGE_KEY_FILE";
  ageKeyFromEnv = builtins.getEnv "VM_AGE_KEY";
  hasAgeKey = ageKeyFromEnv != "" || ageKeyFile != "";
  ageKey =
    if ageKeyFromEnv != "" then ageKeyFromEnv
    else if ageKeyFile != "" then builtins.readFile ageKeyFile
    else "";

  f = builtins.getFlake configDir;
  targetName = if hasAgeKey then "vm-aarch64" else "vm-aarch64-unattended-demo";
  target = f.nixosConfigurations.${targetName};
  pkgs = target.pkgs;
  lib = pkgs.lib;

  excludedSourceNames = [
    ".direnv"
    ".env"
    ".git"
    ".worktrees"
    "result"
  ];
  configSource = builtins.path {
    path = configDir;
    name = "nix-config-source";
    filter = path: type:
      !(builtins.elem (builtins.baseNameOf path) excludedSourceNames);
  };

  installerAgeKey =
    if hasAgeKey then pkgs.writeText "vm-age-identity" ageKey else null;
  installerAuthorizedKey =
    lib.removeSuffix "\n" (builtins.readFile "${configDir}/aspects/network/ssh/m.pub");

  installer = f.inputs.unattended-installer.lib.diskoInstallerWrapper target {
    # The source configuration is embedded, but the target closure is built on
    # the fresh Linux VM. This keeps the ISO small enough to build on the
    # existing aarch64-linux VM while remaining independent of a host share.
    flake = "${configSource}#${targetName}";
    waitForNetwork = true;
    nixosInstallFlags = "--no-channel-copy --no-root-passwd";
    showProgress = true;
    successAction = "poweroff";

    postDisko = lib.optionalString hasAgeKey ''
      ${pkgs.coreutils}/bin/install -d -m 0700 /mnt/var/lib/sops-nix
      ${pkgs.coreutils}/bin/install -m 0600 ${installerAgeKey} /mnt/var/lib/sops-nix/key.txt
    '';

    config = {
      networking.hostName = "nixos-unattended-installer";
      networking.useDHCP = lib.mkForce true;

      # The complete desktop target is built after boot. Give the live ISO's
      # writable Nix-store overlay enough headroom for that closure.
      fileSystems."/nix/.rw-store".options =
        lib.mkForce [ "mode=0755" "size=30G" ];

      virtualisation.vmware.guest.enable = true;

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = lib.mkForce "prohibit-password";
        };
      };
      users.users.root.openssh.authorizedKeys.keys = [ installerAuthorizedKey ];
      networking.firewall.allowedTCPPorts = [ 22 ];
    };
  };
in
  installer.config.system.build.isoImage
