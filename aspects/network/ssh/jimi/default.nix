{ ... }: {
  den.aspects.ssh-pam.jimi = {
    nixos = { ... }: {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitRootLogin = "yes";
        };
      };
    };
  };
}
