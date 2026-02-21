{ inputs, pkgs, ... }:

{
  homebrew = {
    enable = true;
    casks  = [
      "1password"
      "activitywatch"
      "karabiner-elements"
      "claude"
      "discord"
      "gimp"
      "google-chrome"
      "leader-key"
      "lm-studio"
      "loop"
      "mullvad-vpn"
      "rectangle"
      "spotify"
    ];

    brews = [
      "gnupg"
      "kanata"
      "kanata-tray"
    ];

    masApps = {
      "Calflow"    = 6474122188;
      "Journal It"  = 6745241760;
      "Noir"        = 1592917505;
      "Perplexity"  = 6714467650;
      "Tailscale"   = 1475387142;
      "Telegram"    = 747648890;
      "Vimlike"     = 1584519802;
      "Wblock"      = 6746388723;
    };
  };

  # The user should already exist, but we need to set this up so Nix knows
  # what our home directory is (https://github.com/LnL7/nix-darwin/issues/423).
  users.users.m = {
    home = "/Users/m";
    shell = pkgs.zsh;
  };

  # Required for some settings like homebrew to know what user to apply to.
  system.primaryUser = "m";
  services.skhd = {
    enable = true;
    package = pkgs.skhd;
    skhdConfig = builtins.readFile ./skhdrc;
  };


  # Uniclip: encrypted clipboard sharing between macOS and NixOS VM.
  # Server listens on localhost only; an SSH reverse tunnel carries traffic to the VM.
  launchd.user.agents.uniclip = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          /bin/wait4path /nix/store
          export UNICLIP_PASSWORD=$(${pkgs.rbw}/bin/rbw get uniclip-password)
          exec ${pkgs.uniclip}/bin/uniclip --secure --bind 127.0.0.1 -p 53701
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/uniclip-server.log";
      StandardErrorPath = "/tmp/uniclip-server.log";
    };
  };

  # SSH reverse tunnel: forwards the uniclip port into the VM so the VM client
  # can reach the macOS server at 127.0.0.1:53701 on either end.
  launchd.user.agents.uniclip-tunnel = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash" "-c"
        ''
          VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
          VMX="/Users/m/Virtual Machines.localized/NixOS 25.11 aarch64.vmwarevm/NixOS 25.11 aarch64.vmx"
          while true; do
            VM_IP=$("$VMRUN" -T fusion getGuestIPAddress "$VMX" 2>/dev/null)
            if [ -n "$VM_IP" ] && [ "$VM_IP" != "unknown" ]; then
              /usr/bin/ssh -N \
                -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
                -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new \
                -R 53701:127.0.0.1:53701 m@"$VM_IP"
            fi
            sleep 5
          done
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/uniclip-tunnel.log";
      StandardErrorPath = "/tmp/uniclip-tunnel.log";
    };
  };


  launchd.user.agents.kanata-tray = {
    serviceConfig = {
      ProgramArguments = [ "sudo" "/opt/homebrew/bin/kanata-tray" ];
      EnvironmentVariables = {
        KANATA_TRAY_CONFIG_DIR = "/Users/m/.config/kanata-tray";
        KANATA_TRAY_LOG_DIR = "/tmp";
      };
      StandardOutPath = "/tmp/kanata-try.out.log";
      StandardErrorPath = "/tmp/kanata-tray.err.log";
      RunAtLoad = true;
      KeepAlive = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
      ThrottleInterval = 20;
    };
  };
}
