{
  den.hosts.aarch64-linux.vm-aarch64.hostName = "vm-macbook";
  den.hosts.aarch64-linux.vm-aarch64.users.m = { };

  den.hosts.aarch64-darwin.macbook-pro-m1.users.m = { };

  den.hosts.x86_64-linux.wsl.wsl.enable = true;
  den.hosts.x86_64-linux.wsl.users.m = { };

  den.hosts.x86_64-linux.jimi.users.s = {
    isNormalUser = true;
    hashedPassword = "$6$fhySpewi.hTKt.1D$nfheFtKH358q9dKSgrHGsgfzIsot4MgHQiT/A4YMB3hLe00CxTiiGr94qJZGsmFMOIbVMxqGq5emtrWJFWEwD1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+nYJzeeJtFRAHcgcUUcqg7bJUW8MPqVwCSNm1G+LbC m@ms-MacBook-Pro.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtDsEqT1JWzbDo8WeDKlMql6AbcnvzKI1aE46gpHYtv m.liebiediew@gmail.com"
    ];
  };
}
