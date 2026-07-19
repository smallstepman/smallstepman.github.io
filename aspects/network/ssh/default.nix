{ ... }: {
  den.aspects.ssh-pam = {
    darwin = import ./_darwin.nix;

    nixos = { ... }: {
      services.openssh.enable = true;
      services.openssh.settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        X11Forwarding = false;
        PermitRootLogin = "no";
        AllowUsers = [ "m" ];
      };
    };
  };
}
