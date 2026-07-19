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
    # A real installer carries the prebuilt target closure. Installation then
    # copies it directly to the target disk instead of compiling a large desktop
    # closure into the live ISO's RAM-backed writable store. The secret-free
    # demo remains small and exercises the flake-based build path.
    flake = if hasAgeKey then null else "${configSource}#${targetName}";
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
      networking.useDHCP = lib.mkForce false;
      networking.networkmanager.enable = true;
      services.resolved = {
        enable = true;
        settings.Resolve.FallbackDNS = [ "1.1.1.1" "8.8.8.8" ];
      };

      # network-online.target is passive: making the installer wanted by that
      # target does not cause either one to start. Pull it from multi-user.target
      # and wait for the normal NetworkManager online synchronization instead.
      systemd.services.unattended-installer = {
        wantedBy = lib.mkForce [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [ pkgs.git ];
        unitConfig = {
          StartLimitIntervalSec = "30min";
          StartLimitBurst = 3;
        };
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "15s";
        };
      };

      # Generous fallback headroom for installer bookkeeping and for the small
      # secret-free demo's build-on-target path. The real image does not depend
      # on this capacity because its target closure is prebuilt into the ISO.
      fileSystems."/nix/.rw-store".options =
        lib.mkForce [ "mode=0755" "size=48G" ];

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
