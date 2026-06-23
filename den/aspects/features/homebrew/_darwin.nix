{
  homebrew.enable = true;
  homebrew.taps = [
    { name = "lujstn/tap"; trusted = true; }
  ];
  homebrew.casks = [
    "activitywatch"
    "launchcontrol"
    "macfuse"
    "mullvad-vpn"
  ];
  homebrew.brews = [
    "gnupg"
    { name = "pinentry-touchid"; trusted = true; }
    "gromgit/fuse/s3fs-mac"
  ];
  homebrew.masApps = {
    "Tailscale" = 1475387142;
  };
}
