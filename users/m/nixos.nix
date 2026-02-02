{ pkgs, inputs, ... }:

{
  # https://github.com/nix-community/home-manager/pull/2408
  environment.pathsToLink = [ "/share/zsh" ];

  # Add ~/.local/bin to PATH
  environment.localBinInPath = true;

  # Since we're using zsh as our shell
  programs.zsh.enable = true;

  # We require this because we use lazy.nvim against the best wishes
  # a pure Nix system so this lets those unpatched binaries run.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Add any missing dynamic libraries for unpackaged programs
    # here, NOT in environment.systemPackages
  ];

  users.users.m = {
    isNormalUser = true;
    home = "/home/m";
    extraGroups = [ "docker" "lxd" "wheel" ];
    shell = pkgs.zsh;
    hashedPassword = "$6$mTAfbNWiUH$6HLaARy2XAsqXYLx0LcoC4d6/lgaLa3iH/mR891AHez8F/Ya382LN69ZEUddWGhEhHCQK9qEGxTb7GUwjt/7r.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbTIKIPtrymhvtTvqbU07/e7gyFJqNS4S0xlfrZLOaY m"
    ];
  };
}
