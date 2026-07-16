{ inputs }: { lib, pkgs, ... }: {
  homebrew.casks = [ "karabiner-elements" "leader-key" ];

  security.sudo.extraConfig = ''
    m ALL=(root) NOPASSWD: /usr/bin/env KANATA_TRAY_CONFIG_DIR\=/Users/m/Library/Application\ Support/kanata-tray ${lib.getExe' (inputs.kanata-tray.packages.${pkgs.stdenv.hostPlatform.system}.default) "kanata-tray"}
  '';

  home-manager.users.m = { config, lib, pkgs, ... }: let
    kanata = inputs.nixpkgs-master.legacyPackages.${pkgs.stdenv.hostPlatform.system}.kanata.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/oskbd/macos.rs \
          --replace-fail "        ensure_accessibility_permission()?;" \
            "        // AXIsProcessTrusted reports the launchd/sudo responsible process for CLI services.
        // The actual IOHID/Karabiner open path below still enforces TCC.
        // ensure_accessibility_permission()?;"
      '';
    });
  in {
    imports = [ inputs.kanata-tray.homeManagerModules.default ];
    _module.args.hostPlatform = pkgs.stdenv.hostPlatform;

    home.file."Library/Application Support/kanata-tray/status_icons" = {
      source = ./tray/status_icons;
      recursive = true;
    };
    xdg.configFile = {
      "kanata" = {
        source = ./config-macbook-iso;
        recursive = true;
      };
    };
    home.packages = [ kanata ];

    programs.kanata-tray = {
      enable = true;
      package = inputs.kanata-tray.packages.${pkgs.stdenv.hostPlatform.system}.default;
      settings = {
        "$schema" = "https://raw.githubusercontent.com/rszyma/kanata-tray/main/doc/config_schema.json";

        general = {
          allow_concurrent_presets = false;
          control_server_enable = false;
          control_server_port = 8100;
        };

        defaults = {
          tcp_port = 5829;
          autorestart_on_crash = false;
          kanata_executable = "${config.home.profileDirectory}/bin/kanata";
        };

        presets = {
          "Default Preset" = {
            kanata_config = "${config.xdg.configHome}/kanata/config.kbd";
            autorun = true;
          };
          "Gaming Preset" = {
            kanata_config = "${config.xdg.configHome}/kanata/gaming.kbd";
            autorun = false;
          };
        };
      };
    };

    launchd.agents.kanata-tray = {
      enable = true;
      config = {
        Label = "org.nixos.kanata-tray";
        ProgramArguments = [
          "/usr/bin/sudo"
          "-n"
          "/usr/bin/env"
          "KANATA_TRAY_CONFIG_DIR=/Users/m/Library/Application Support/kanata-tray"
          (lib.getExe' (inputs.kanata-tray.packages.${pkgs.stdenv.hostPlatform.system}.default) "kanata-tray")
        ];
        StandardOutPath = "/tmp/kanata-tray.out.log";
        StandardErrorPath = "/tmp/kanata-tray.err.log";
        RunAtLoad = true;
        KeepAlive = true;
        LimitLoadToSessionType = "Aqua";
        ProcessType = "Interactive";
        ThrottleInterval = 20;
      };
    };
  };
}
