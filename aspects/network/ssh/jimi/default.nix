{ ... }: {
  den.aspects.ssh-pam.jimi = {
    nixos = { ... }: {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };
    };
  };
}
