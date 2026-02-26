{ config, pkgs, ... }:

{
  nix = {
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  nixpkgs.config.permittedInsecurePackages = [
    "mupdf-1.17.0"
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.settings.X11Forwarding = false;
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.AllowUsers = [ "m" ];

  # Firewall: trust VMware NAT + Tailscale interfaces.
  # enp+ covers the VMware virtual NIC inside the guest (enp2s0).
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" "enp+" ];
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };
}
