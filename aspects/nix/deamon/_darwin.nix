{
  system.stateVersion = 5;
  ids.gids.nixbld = 30000;

  nix.enable = false;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
    keep-outputs = true
    keep-derivations = true
  '';

  nix.linux-builder = {
    enable = false;
    ephemeral = true;
    maxJobs = 4;
    config = ({ pkgs, ... }: {
      virtualisation.cores = 6;
      virtualisation.darwin-builder.diskSize = 100 * 1024;
      virtualisation.darwin-builder.memorySize = 32 * 1024;
      environment.systemPackages = [ pkgs.htop ];
    });
  };

  nix.settings.trusted-users = [ "@admin" ];

  environment.etc."nix/nix.conf".text = ''
    build-users-group = nixbld
    !include /etc/nix/nix.custom.conf
  '';
  environment.etc."nix/nix.custom.conf".text = ''
    experimental-features = nix-command flakes
  '';
  environment.etc."nixpkgs/config.nix".text = ''
    { allowUnfree = true; }
  '';
}
