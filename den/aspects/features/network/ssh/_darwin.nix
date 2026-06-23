{ generated, ... }: {
  users.users.m = {
    home = "/Users/m";
    openssh.authorizedKeys.keyFiles = [
      (generated.requireFile "mac-host-authorized-keys")
      (generated.requireFile "touchid-bridge-vm-user-to-mac.pub")
      (generated.requireFile "touchid-bridge-vm-root-to-mac.pub")
    ];
  };

  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    # Only listen on the VMware host/guest interface so sshd is not reachable
    # from other network interfaces (Wi-Fi, Ethernet, etc.).
    ListenAddress 192.168.130.1
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PermitRootLogin no
    X11Forwarding no
    AllowUsers m
  '';
}
