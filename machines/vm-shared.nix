{ config, pkgs, lib, currentSystem, currentSystemName, inputs, ... }:

{
  sops.hostPubKey = lib.removeSuffix "\n" (builtins.readFile ./generated/vm-age-pubkey);

  imports = [
    ./profiles/base.nix
    ./profiles/desktop.nix
  ];

  # Be careful updating this.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # VMware, Parallels both only support this being 0 otherwise you see
  # "error switching console mode" on boot.
  boot.loader.systemd-boot.consoleMode = "0";

  # Define your hostname.
  networking.hostName = "vm-macbook";
  networking.hosts."127.0.0.1" = [ "vm-macbook" "localhost" ];
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

  # Set your time zone.
  time.timeZone = "Europe/Warsaw";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;

  # Enable NetworkManager (was previously pulled in by GNOME)
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";
  services.resolved = {
    enable = true;
    fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
  };

  # Require password for sudo but cache it for 10 minutes.
  # Blocks automated privilege escalation (LLM agents, malicious deps)
  # while staying low-friction for interactive use.
  security.sudo.wheelNeedsPassword = true;
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=10
  '';

  # Virtualization settings
  virtualisation.docker.enable = true;

  # Enable tailscale. We manually authenticate when we want with
  # "sudo tailscale up". If you don't use tailscale, you should comment
  # out or delete all of this.
  services.tailscale.enable = true;
  services.tailscale.authKeyFile = config.sops.secrets."tailscale/auth-key".path;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.mutableUsers = false;

  # Manage fonts. We pull these from a secret directory since most of these
  # fonts require a purchase.
  fonts = {
    fontDir.enable = true;

    packages = [
      pkgs.fira-code
      pkgs.jetbrains-mono
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    cachix
    gnumake
    git          # needed for niri-flake build
    killall
    wl-clipboard  # Wayland clipboard

    # Ghostty terminal
    inputs.ghostty.packages.${currentSystem}.default
  ] ++ lib.optionals (currentSystemName == "vm-aarch64") [
    # This is needed for the vmware user tools clipboard to work.
    # You can test if you don't need this by deleting this and seeing
    # if the clipboard sill works.
    gtkmm3
  ];

  # Secrets management (sops-nix + sopsidy)
  # VM pubkey is read from machines/generated/vm-age-pubkey when present.
  sops.defaultSopsFile = ./secrets.yaml;
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?
}
